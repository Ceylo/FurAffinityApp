//
//  PersistentLoggerTests.swift
//  FALoggingTests
//

import XCTest
@testable import FALogging

final class PersistentLoggerTests: XCTestCase {
    private var tempDir: URL!
    private var store: PersistentLogStore!
    private var logger: PersistentLogger!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FALoggerTests-\(UUID().uuidString)", isDirectory: true)
        store = PersistentLogStore(directory: tempDir, maxTotalBytes: 10 * 1024 * 1024)
        logger = PersistentLogger(subsystem: "net.test", category: "FAKit", store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testDualWritePersistsEachLevelWithCategory() {
        logger.debug("a debug line")
        logger.info("got \(3) items")
        logger.warning("a warning")
        logger.error("failed: \("boom", privacy: .public)")
        let text = String(data: store.readAllForExport(), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("[FAKit] [debug] a debug line"), text)
        XCTAssertTrue(text.contains("[FAKit] [info] got 3 items"), text)
        XCTAssertTrue(text.contains("[FAKit] [warning] a warning"), text)
        XCTAssertTrue(text.contains("[FAKit] [error] failed: boom"), text)
    }

    func testCategoryIsRecorded() {
        let other = PersistentLogger(subsystem: "net.test", category: "FAPages", store: store)
        other.info("parsed page")
        let text = String(data: store.readAllForExport(), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("[FAPages] [info] parsed page"), text)
    }
}
