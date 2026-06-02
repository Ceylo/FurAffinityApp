//
//  PersistentLogStoreTests.swift
//  FALoggingTests
//

import XCTest
@testable import FALogging

final class PersistentLogStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FALoggingTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func diskUsage(_ dir: URL) throws -> Int {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return try urls.reduce(0) { total, url in
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            return total + size
        }
    }

    func testAppendThenExportRoundTrips() {
        let store = PersistentLogStore(directory: tempDir, maxTotalBytes: 10 * 1024 * 1024)
        store.append(category: "FA", level: "info", message: "hello world")
        store.append(category: "FAKit", level: "error", message: "boom")

        let text = String(data: store.readAllForExport(), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("[FA] [info] hello world"), text)
        XCTAssertTrue(text.contains("[FAKit] [error] boom"), text)
    }

    func testRotationKeepsTotalUnderCap() throws {
        // Small cap so rotation triggers quickly: 8 KB total -> 4 KB per file.
        let cap = 8 * 1024
        let store = PersistentLogStore(directory: tempDir, maxTotalBytes: cap)
        let payload = String(repeating: "x", count: 120)
        for i in 0..<2_000 {
            store.append(category: "FA", level: "info", message: "\(i) \(payload)")
        }
        store.flush() // writes are async; ensure they land before inspecting disk

        // At most active + one rotated file, each capped near maxFileBytes.
        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertLessThanOrEqual(files.count, 2, "expected at most 2 rotation files, got \(files)")
        // Allow one over-cap line per file beyond the byte budget.
        let oneLineSlack = 256
        XCTAssertLessThanOrEqual(try diskUsage(tempDir), cap + oneLineSlack)
    }

    func testRotationPreservesMostRecentEntries() {
        let store = PersistentLogStore(directory: tempDir, maxTotalBytes: 8 * 1024)
        let payload = String(repeating: "y", count: 120)
        for i in 0..<2_000 {
            store.append(category: "FA", level: "info", message: "line-\(i) \(payload)")
        }
        let text = String(data: store.readAllForExport(), encoding: .utf8) ?? ""
        // The newest line must survive; the oldest must have been dropped.
        XCTAssertTrue(text.contains("line-1999"), "most recent entry missing")
        XCTAssertFalse(text.contains("line-0 "), "oldest entry should have rotated out")
    }

    func testNewInstanceAppendsToExistingFiles() {
        let first = PersistentLogStore(directory: tempDir, maxTotalBytes: 10 * 1024 * 1024)
        first.append(category: "FA", level: "info", message: "before relaunch")
        first.flush() // ensure it reaches disk before the "new process" reads

        // Simulate a fresh process pointing at the same directory.
        let second = PersistentLogStore(directory: tempDir, maxTotalBytes: 10 * 1024 * 1024)
        second.append(category: "FA", level: "info", message: "after relaunch")

        let text = String(data: second.readAllForExport(), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("before relaunch"), text)
        XCTAssertTrue(text.contains("after relaunch"), text)
    }

    // MARK: - Caller latency benchmark
    //
    // The write path is async (decided from the sync-path benchmark: sync tail
    // latency reached 4.3 ms with no rotation and 31.8 ms on rotation, which
    // would hitch main-thread frames). These tests confirm the *caller*-observed
    // cost of append() is now negligible because file I/O happens off-thread.

    /// Times the caller-observed cost of append() and prints mean/p50/p99/max.
    func testAppendCallerLatency() {
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
        store.flush()

        printLatencyStats("async append - caller cost (no rotation)", nanos)
        XCTAssertLessThan(percentile(nanos, 0.99), 5_000_000, "p99 caller latency unexpectedly high")
    }

    /// Same, but with frequent rotation: caller cost should stay low because
    /// rotation runs on the serial queue, not the caller's thread.
    func testAppendCallerLatencyWithRotation() {
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
        store.flush()
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
