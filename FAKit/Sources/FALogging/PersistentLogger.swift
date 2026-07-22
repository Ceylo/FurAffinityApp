//
//  PersistentLogger.swift
//  FALogging
//
//  Drop-in replacement for `os.Logger` that dual-writes: each entry is appended
//  to the persistent rotating file (PersistentLogStore) AND forwarded to the
//  matching os.Logger method so the Xcode Console keeps its native category and
//  level metadata.
//
//  Note: Console's "source" attribution points at this file rather than the
//  call site, because os.Logger derives it from the os_log call address and
//  there is no API to forward the caller's #file/#line. That is an inherent
//  cost of wrapping os.Logger; the message text is left untouched.
//

import Foundation
#if canImport(os)
import os
#endif

public struct PersistentLogger: Sendable {
    #if canImport(os)
    private let osLogger: os.Logger
    #endif
    private let category: String
    private let store: PersistentLogStore

    public init(subsystem: String, category: String, store: PersistentLogStore = .shared) {
        #if canImport(os)
        self.osLogger = os.Logger(subsystem: subsystem, category: category)
        #endif
        self.category = category
        self.store = store
    }

    public func trace(_ message: FALogMessage) {
        store.append(category: category, level: "trace", message: message.rendered)
        #if canImport(os)
        osLogger.trace("\(message.rendered)")
        #endif
    }

    public func debug(_ message: FALogMessage) {
        store.append(category: category, level: "debug", message: message.rendered)
        #if canImport(os)
        osLogger.debug("\(message.rendered)")
        #endif
    }

    public func info(_ message: FALogMessage) {
        store.append(category: category, level: "info", message: message.rendered)
        #if canImport(os)
        osLogger.info("\(message.rendered)")
        #endif
    }

    public func notice(_ message: FALogMessage) {
        store.append(category: category, level: "notice", message: message.rendered)
        #if canImport(os)
        osLogger.notice("\(message.rendered)")
        #endif
    }

    public func warning(_ message: FALogMessage) {
        store.append(category: category, level: "warning", message: message.rendered)
        #if canImport(os)
        osLogger.warning("\(message.rendered)")
        #endif
    }

    public func error(_ message: FALogMessage) {
        store.append(category: category, level: "error", message: message.rendered)
        #if canImport(os)
        osLogger.error("\(message.rendered)")
        #endif
    }

    public func critical(_ message: FALogMessage) {
        store.append(category: category, level: "critical", message: message.rendered)
        #if canImport(os)
        osLogger.critical("\(message.rendered)")
        #endif
    }

    public func fault(_ message: FALogMessage) {
        store.append(category: category, level: "fault", message: message.rendered)
        #if canImport(os)
        osLogger.fault("\(message.rendered)")
        #endif
    }

    public func log(_ message: FALogMessage) {
        store.append(category: category, level: "default", message: message.rendered)
        #if canImport(os)
        osLogger.log("\(message.rendered)")
        #endif
    }
}
