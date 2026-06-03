//
//  PersistentLogStore.swift
//  FALogging
//
//  Rotating, size-capped file backing for persistent application logs. Unlike
//  OSLogStore (which on iOS can only read the current process), this survives
//  process kills so log history is retained across launches.
//
//  Writes are asynchronous and batched. append() never touches the file: it
//  buffers the entry and, if no write is already pending, schedules one on a
//  serial queue. Entries that arrive while a write is in flight are coalesced
//  into the next batch, and a fresh write is scheduled the moment the previous
//  one finishes. This keeps the caller (often the main actor) off the file I/O
//  path — measured caller cost is single-digit microseconds — while writing
//  promptly without any explicit flush/lifecycle wiring.
//

import Foundation

public final class PersistentLogStore: @unchecked Sendable {
    /// Process-wide store writing to Application Support/Logs.
    public static let shared = PersistentLogStore()

    /// Owns all file I/O and `handle`/`currentSize`; it is their single access
    /// point, so they need no extra lock.
    private let queue = DispatchQueue(label: "net.furaffinity.persistentlog", qos: .utility)
    private let directory: URL
    /// Per-file byte cap. Total on-disk budget is roughly `2 * maxFileBytes`
    /// (active file + one rotated file).
    private let maxFileBytes: Int
    private let activeURL: URL
    private let previousURL: URL
    private let formatter: ISO8601DateFormatter

    private struct Entry {
        let date: Date
        let category: String
        let level: String
        let message: String
    }

    /// Producer/consumer buffer for not-yet-written entries. Guarded by `bufferLock`.
    private let bufferLock = NSLock()
    private var pending: [Entry] = []
    private var drainScheduled = false

    // Touched only on `queue`.
    private var handle: FileHandle?
    private var currentSize: Int = 0

    /// - Parameters:
    ///   - directory: where log files live. Defaults to Application Support/Logs.
    ///     Injectable for tests.
    ///   - maxTotalBytes: total on-disk budget across both rotation files.
    public init(directory: URL? = nil, maxTotalBytes: Int = 10 * 1024 * 1024) {
        self.maxFileBytes = max(1, maxTotalBytes / 2)
        let dir = directory ?? PersistentLogStore.defaultDirectory()
        self.directory = dir
        self.activeURL = dir.appendingPathComponent("app.log")
        self.previousURL = dir.appendingPathComponent("app.1.log")
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = fmt
        // Enqueued first, so it runs before any drain on the serial queue.
        queue.async { [self] in openActive() }
    }

    private static func defaultDirectory() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Logs", isDirectory: true)
    }

    // MARK: - Public API

    /// Buffer one log entry for asynchronous writing. Returns immediately; the
    /// file write happens on the serial queue, batched with any other entries
    /// that arrive before it runs. Never throws and never crashes: on any I/O
    /// failure the batch is silently dropped from the file (the os.Logger mirror
    /// still receives it).
    public func append(category: String, level: String, message: String) {
        let entry = Entry(date: Date(), category: category, level: level, message: message)
        bufferLock.lock()
        pending.append(entry)
        let needsSchedule = !drainScheduled
        if needsSchedule { drainScheduled = true }
        bufferLock.unlock()

        if needsSchedule {
            queue.async { [self] in writePendingBatch() }
        }
    }

    /// Concatenated log contents, oldest (rotated) file first, for export. Runs
    /// on the queue and writes any buffered entries first, so the export
    /// includes everything appended so far.
    public func readAllForExport() -> Data {
        queue.sync {
            writePendingBatch()
            var data = Data()
            if let previous = try? Data(contentsOf: previousURL) {
                data.append(previous)
            }
            if let active = try? Data(contentsOf: activeURL) {
                data.append(active)
            }
            return data
        }
    }

    /// Delete all persisted logs (and any buffered entries) and start fresh.
    public func clear() {
        queue.sync {
            bufferLock.lock()
            pending.removeAll()
            drainScheduled = false
            bufferLock.unlock()

            try? handle?.close()
            handle = nil
            try? FileManager.default.removeItem(at: activeURL)
            try? FileManager.default.removeItem(at: previousURL)
            openActive()
        }
    }

    // MARK: - Internals (all run on `queue`)

    /// Drain the buffer and write it to disk as a single batch. Clearing
    /// `drainScheduled` under the buffer lock guarantees that any entry appended
    /// after this point schedules a fresh write, so nothing is lost.
    private func writePendingBatch() {
        bufferLock.lock()
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        drainScheduled = false
        bufferLock.unlock()

        guard !batch.isEmpty else { return }

        var data = Data()
        for entry in batch {
            let line = "\(formatter.string(from: entry.date)) [\(entry.category)] [\(entry.level)] \(entry.message)\n"
            if let bytes = line.data(using: .utf8) {
                data.append(bytes)
            }
        }
        write(data)
    }

    private func openActive() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: activeURL.path) {
                FileManager.default.createFile(atPath: activeURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: activeURL)
            let end = try handle.seekToEnd()
            self.handle = handle
            self.currentSize = Int(end)
        } catch {
            self.handle = nil
            self.currentSize = 0
        }
    }

    /// Write a (possibly large, batched) blob, rotating whenever the active file
    /// reaches the per-file cap. Chunking mid-blob keeps each file strictly under
    /// `maxFileBytes` even for bursts larger than the cap; a log line split across
    /// the boundary is reassembled by `readAllForExport`, which concatenates the
    /// files in order.
    private func write(_ data: Data) {
        let total = data.count
        var offset = 0
        while offset < total {
            if currentSize >= maxFileBytes {
                rotate()
            }
            guard let handle else { return }
            let room = max(1, maxFileBytes - currentSize)
            let chunkLength = min(room, total - offset)
            let chunk = data.subdata(in: offset..<(offset + chunkLength))
            do {
                try handle.write(contentsOf: chunk)
                currentSize += chunkLength
            } catch {
                // Drop the rest of the batch rather than ever crashing the caller.
                return
            }
            offset += chunkLength
        }
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: previousURL)
        try? fileManager.moveItem(at: activeURL, to: previousURL)
        openActive()
    }
}
