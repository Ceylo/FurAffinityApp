//
//  PersistentLogger.swift
//  FALogging
//
//  Drop-in replacement for `os.Logger` that dual-writes: each entry is appended
//  to the persistent rotating file (PersistentLogStore) AND forwarded to the
//  matching os.Logger method so the Xcode Console keeps its native category and
//  level metadata. Call sites use the same `logger.info("... \(x, privacy:
//  .public) ...")` syntax as before (see FALogMessage).
//

import Foundation
import os

public struct PersistentLogger: Sendable {
    private let osLogger: os.Logger
    private let category: String
    private let store: PersistentLogStore

    public init(subsystem: String, category: String, store: PersistentLogStore = .shared) {
        self.osLogger = os.Logger(subsystem: subsystem, category: category)
        self.category = category
        self.store = store
    }

    public func trace(_ message: FALogMessage) {
        store.append(category: category, level: "trace", message: message.rendered)
        osLogger.trace("\(message.rendered, privacy: .public)")
    }

    public func debug(_ message: FALogMessage) {
        store.append(category: category, level: "debug", message: message.rendered)
        osLogger.debug("\(message.rendered, privacy: .public)")
    }

    public func info(_ message: FALogMessage) {
        store.append(category: category, level: "info", message: message.rendered)
        osLogger.info("\(message.rendered, privacy: .public)")
    }

    public func notice(_ message: FALogMessage) {
        store.append(category: category, level: "notice", message: message.rendered)
        osLogger.notice("\(message.rendered, privacy: .public)")
    }

    public func warning(_ message: FALogMessage) {
        store.append(category: category, level: "warning", message: message.rendered)
        osLogger.warning("\(message.rendered, privacy: .public)")
    }

    public func error(_ message: FALogMessage) {
        store.append(category: category, level: "error", message: message.rendered)
        osLogger.error("\(message.rendered, privacy: .public)")
    }

    public func critical(_ message: FALogMessage) {
        store.append(category: category, level: "critical", message: message.rendered)
        osLogger.critical("\(message.rendered, privacy: .public)")
    }

    public func fault(_ message: FALogMessage) {
        store.append(category: category, level: "fault", message: message.rendered)
        osLogger.fault("\(message.rendered, privacy: .public)")
    }

    public func log(_ message: FALogMessage) {
        store.append(category: category, level: "default", message: message.rendered)
        osLogger.log("\(message.rendered, privacy: .public)")
    }
}
