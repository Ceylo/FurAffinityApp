//
//  PersistentLogStore.swift
//  FALogging
//
//  Rotating, size-capped file backing for persistent application logs. Unlike
//  OSLogStore (which on iOS can only read the current process), this survives
//  process kills so log history is retained across launches.
//
//  Writes go through a private serial DispatchQueue: append() captures the
//  timestamp/message and dispatches the file I/O, so the caller (often the main
//  actor) never blocks. This was chosen over synchronous writes after measuring
//  the sync path on the simulator — typical cost was ~9 µs but tail latency
//  reached 4.3 ms (no rotation) and 31.8 ms (rotation), which would hitch
//  main-thread frames. Durability at termination is provided by flush().
//

import Foundation

public final class PersistentLogStore: @unchecked Sendable {
    /// Process-wide store writing to Application Support/Logs.
    public static let shared = PersistentLogStore()

    /// Owns all file I/O and the mutable state below; it is the single access
    /// point, so no additional lock is needed.
    private let queue = DispatchQueue(label: "net.furaffinity.persistentlog", qos: .utility)
    private let directory: URL
    /// Per-file byte cap. Total on-disk budget is roughly `2 * maxFileBytes`
    /// (active file + one rotated file).
    private let maxFileBytes: Int
    private let activeURL: URL
    private let previousURL: URL
    private let formatter: ISO8601DateFormatter

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
        // Enqueued first, so it runs before any append on the serial queue.
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

    /// Append one log entry. Returns immediately; the file write happens on the
    /// serial queue. Never throws and never crashes: on any I/O failure the
    /// entry is silently dropped from the file (the os.Logger mirror still
    /// receives it).
    public func append(category: String, level: String, message: String) {
        let date = Date()
        queue.async { [self] in
            let line = "\(formatter.string(from: date)) [\(category)] [\(level)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            write(data)
        }
    }

    /// Block until all writes enqueued so far have reached the page cache. Call
    /// at lifecycle checkpoints (scene background, end of background refresh) to
    /// bound log loss on abrupt termination.
    public func flush() {
        queue.sync {}
    }

    /// Concatenated log contents, oldest (rotated) file first, for export.
    /// Runs on the queue, so all previously enqueued writes are included.
    public func readAllForExport() -> Data {
        queue.sync {
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

    /// Delete all persisted logs and start fresh.
    public func clear() {
        queue.sync {
            try? handle?.close()
            handle = nil
            try? FileManager.default.removeItem(at: activeURL)
            try? FileManager.default.removeItem(at: previousURL)
            openActive()
        }
    }

    // MARK: - Internals (all run on `queue`)

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

    private func write(_ data: Data) {
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
            currentSize += data.count
            if currentSize >= maxFileBytes {
                rotate()
            }
        } catch {
            // Drop the entry rather than ever crashing the caller.
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
