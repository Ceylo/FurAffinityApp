//
//  Logs.swift
//  FurAffinity
//
//  Created by Ceylo on 12/10/2022.
//

import Foundation
import OSLog

let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FA")

extension OSLogEntryLog.Level: CustomStringConvertible {
    public var description: String {
        switch self {
        case .undefined: return "undefined"
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        case .fault: return "fault"
        @unknown default: return "unknown"
        }
    }
}

func generateLogFile() throws -> URL {
    let logStore = try OSLogStore(scope: .currentProcessIdentifier)
    let position = logStore.position(date: Date().addingTimeInterval(-300))
    let allEntries = try logStore.getEntries(at: position)
    let subsystem = Bundle.main.bundleIdentifier!
    let logs = allEntries
        .compactMap { $0 as? OSLogEntryLog }
        .filter { $0.subsystem == subsystem }
        .map { "\($0.date) [\($0.category)] [\($0.level)] \($0.composedMessage)" }
        .joined(separator: "\n")
    let data = logs.data(using: .utf8)!
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("FurAffinity App Logs.txt")
    try data.write(to: url)
    return url
}
