//
//  PersistentLogStoreTests.swift
//  FALoggingTests
//

import Testing
import Foundation
@testable import FALogging

final class PersistentLogStoreTests {
    private let tempDir: URL

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FALoggingTests-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func diskUsage(_ dir: URL) throws -> Int {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return try urls.reduce(0) { total, url in
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            return total + size
        }
    }

    @Test
    func appendThenExportRoundTrips() {
        let store = PersistentLogStore(directory: tempDir, maxTotalBytes: 10 * 1024 * 1024)
        store.append(category: "FA", level: "info", message: "hello world")
        store.append(category: "FAKit", level: "error", message: "boom")

        let text = String(data: store.readAllForExport(), encoding: .utf8) ?? ""
        #expect(text.contains("[FA] [info] hello world"), "\(text)")
        #expect(text.contains("[FAKit] [error] boom"), "\(text)")
    }

    @Test
    func rotationKeepsTotalUnderCap() throws {
        // Small cap so rotation triggers quickly: 8 KB total -> 4 KB per file.
        let cap = 8 * 1024
        let store = PersistentLogStore(directory: tempDir, maxTotalBytes: cap)
        // A fast burst coalesces into large batches, so this also exercises the
        // chunked write path that keeps each file under the cap mid-batch.
        let payload = String(repeating: "x", count: 120)
        for i in 0..<2_000 {
            store.append(category: "FA", level: "info", message: "\(i) \(payload)")
        }
        // Writes are async; readAllForExport drains buffered entries to disk.
        _ = store.readAllForExport()

        // At most active + one rotated file, each capped at maxFileBytes.
        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        #expect(files.count <= 2, "expected at most 2 rotation files, got \(files)")
        #expect(try diskUsage(tempDir) <= cap)
    }

    @Test
    func rotationPreservesMostRecentEntries() {
        let store = PersistentLogStore(directory: tempDir, maxTotalBytes: 8 * 1024)
        let payload = String(repeating: "y", count: 120)
        for i in 0..<2_000 {
            store.append(category: "FA", level: "info", message: "line-\(i) \(payload)")
        }
        let text = String(data: store.readAllForExport(), encoding: .utf8) ?? ""
        // The newest line must survive; the oldest must have been dropped.
        #expect(text.contains("line-1999"), "most recent entry missing")
        #expect(!text.contains("line-0 "), "oldest entry should have rotated out")
    }

    @Test
    func readForExportNilReturnsEverything() {
        let store = PersistentLogStore(directory: tempDir, maxTotalBytes: 10 * 1024 * 1024)
        store.append(category: "FA", level: "info", message: "hello world")
        store.append(category: "FAKit", level: "error", message: "boom")

        #expect(store.readForExport(since: nil) == store.readAllForExport())
    }

    @Test
    func readForExportFiltersByCutoff() {
        let store = PersistentLogStore(directory: tempDir, maxTotalBytes: 10 * 1024 * 1024)
        // append() stamps Date() internally, so drive the cutoff relative to now.
        let now = Date()
        store.append(category: "FA", level: "info", message: "alpha")
        store.append(category: "FAKit", level: "error", message: "beta")

        // A cutoff slightly in the past keeps every just-appended entry.
        let kept = String(data: store.readForExport(since: now.addingTimeInterval(-60)), encoding: .utf8) ?? ""
        #expect(kept.contains("alpha"), "\(kept)")
        #expect(kept.contains("beta"), "\(kept)")

        // A cutoff in the future drops them all.
        let dropped = String(data: store.readForExport(since: now.addingTimeInterval(60)), encoding: .utf8) ?? ""
        #expect(!dropped.contains("alpha"), "\(dropped)")
        #expect(!dropped.contains("beta"), "\(dropped)")
    }

    @Test
    func readForExportKeepsMultiLineMessageWhole() {
        let store = PersistentLogStore(directory: tempDir, maxTotalBytes: 10 * 1024 * 1024)
        let now = Date()
        store.append(category: "FA", level: "info", message: "line one\nline two\nline three")

        // The whole multi-line message survives a past cutoff...
        let kept = String(data: store.readForExport(since: now.addingTimeInterval(-60)), encoding: .utf8) ?? ""
        #expect(kept.contains("line one"), "\(kept)")
        #expect(kept.contains("line two"), "\(kept)")
        #expect(kept.contains("line three"), "\(kept)")

        // ...and is dropped as a whole for a future cutoff (continuation lines
        // inherit the leading line's decision).
        let dropped = String(data: store.readForExport(since: now.addingTimeInterval(60)), encoding: .utf8) ?? ""
        #expect(!dropped.contains("line two"), "\(dropped)")
        #expect(!dropped.contains("line three"), "\(dropped)")
    }

    @Test
    func newInstanceAppendsToExistingFiles() {
        let first = PersistentLogStore(directory: tempDir, maxTotalBytes: 10 * 1024 * 1024)
        first.append(category: "FA", level: "info", message: "before relaunch")
        _ = first.readAllForExport() // drain to disk before the "new process" reads

        // Simulate a fresh process pointing at the same directory.
        let second = PersistentLogStore(directory: tempDir, maxTotalBytes: 10 * 1024 * 1024)
        second.append(category: "FA", level: "info", message: "after relaunch")

        let text = String(data: second.readAllForExport(), encoding: .utf8) ?? ""
        #expect(text.contains("before relaunch"), "\(text)")
        #expect(text.contains("after relaunch"), "\(text)")
    }

    // MARK: - Caller latency benchmark
    //
    // The write path is async (decided from a sync-path benchmark: sync tail
    // latency reached 4.3 ms / 31.8 ms, which would hitch main-thread frames).
    // These confirm the *caller*-observed cost of append() is negligible because
    // file I/O happens off-thread.

    @Test
    func appendCallerLatency() {
        let store = PersistentLogStore(directory: tempDir, maxTotalBytes: 10 * 1024 * 1024)
        let message = "[CFDIAG] CloudFlare background resolution attempt for "
            + "https://www.furaffinity.net/msg/submissions/ state=active retry=2"

        let iterations = 10_000
        var nanos = [Double](repeating: 0, count: iterations)
        let clock = ContinuousClock()
        for i in 0..<iterations {
            let start = clock.now
            store.append(category: "FAKit", level: "info", message: "\(i) \(message)")
            nanos[i] = Double((clock.now - start).components.attoseconds) / 1_000_000_000.0
        }
        _ = store.readAllForExport()

        printLatencyStats("async append - caller cost (no rotation)", nanos)
        #expect(percentile(nanos, 0.99) < 5_000_000, "p99 caller latency unexpectedly high")
    }

    @Test
    func appendCallerLatencyWithRotation() {
        let store = PersistentLogStore(directory: tempDir, maxTotalBytes: 64 * 1024)
        let payload = String(repeating: "z", count: 120)

        let iterations = 10_000
        var nanos = [Double](repeating: 0, count: iterations)
        let clock = ContinuousClock()
        for i in 0..<iterations {
            let start = clock.now
            store.append(category: "FAKit", level: "info", message: "\(i) \(payload)")
            nanos[i] = Double((clock.now - start).components.attoseconds) / 1_000_000_000.0
        }
        _ = store.readAllForExport()
        printLatencyStats("async append - caller cost (frequent rotation)", nanos)
    }

    private func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        let idx = min(sorted.count - 1, max(0, Int((Double(sorted.count) * p).rounded(.down))))
        return sorted[idx]
    }

    private func printLatencyStats(_ label: String, _ nanos: [Double]) {
        let mean = nanos.reduce(0, +) / Double(nanos.count)
        let p50 = percentile(nanos, 0.50)
        let p99 = percentile(nanos, 0.99)
        let maxv = nanos.max() ?? 0
        func us(_ ns: Double) -> String { String(format: "%.3f µs", ns / 1000) }
        print("LATENCY[\(label)] n=\(nanos.count) mean=\(us(mean)) p50=\(us(p50)) p99=\(us(p99)) max=\(us(maxv))")
    }
}
