//
//  PersistentLoggerTests.swift
//  FALoggingTests
//

import Testing
import Foundation
@testable import FALogging

final class PersistentLoggerTests {
    private let tempDir: URL
    private let store: PersistentLogStore
    private let logger: PersistentLogger

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FALoggerTests-\(UUID().uuidString)", isDirectory: true)
        store = PersistentLogStore(directory: tempDir, maxTotalBytes: 10 * 1024 * 1024)
        logger = PersistentLogger(subsystem: "net.test", category: "FAKit", store: store)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test
    func dualWritePersistsEachLevelWithCategory() {
        logger.debug("a debug line")
        logger.info("got \(3) items")
        logger.warning("a warning")
        logger.error("failed: \("boom")")

        let text = String(data: store.readAllForExport(), encoding: .utf8) ?? ""
        #expect(text.contains("[FAKit] [debug] a debug line"), "\(text)")
        #expect(text.contains("[FAKit] [info] got 3 items"), "\(text)")
        #expect(text.contains("[FAKit] [warning] a warning"), "\(text)")
        #expect(text.contains("[FAKit] [error] failed: boom"), "\(text)")
    }

    @Test
    func categoryIsRecorded() {
        let other = PersistentLogger(subsystem: "net.test", category: "FAPages", store: store)
        other.info("parsed page")

        let text = String(data: store.readAllForExport(), encoding: .utf8) ?? ""
        #expect(text.contains("[FAPages] [info] parsed page"), "\(text)")
    }
}
