//
//  Logs.swift
//  FurAffinity
//
//  Created by Ceylo on 12/10/2022.
//

import Foundation
import OSLog
import FALogging

let logger = PersistentLogger(subsystem: Bundle.main.bundleIdentifier!, category: "FA")
private let signpostLog = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FA")
let signposter = OSSignposter(logger: signpostLog)

/// The time window to include when exporting application logs.
enum LogExportRange {
    case lastHour
    case last24Hours
    case all

    /// Cutoff date for filtering, or `nil` to export everything.
    fileprivate var cutoff: Date? {
        switch self {
        case .lastHour: Date().addingTimeInterval(-3600)
        case .last24Hours: Date().addingTimeInterval(-86400)
        case .all: nil
        }
    }

    /// Filename fragment so each range produces a distinguishable export.
    fileprivate var filenameSuffix: String {
        switch self {
        case .lastHour: "last hour"
        case .last24Hours: "last 24h"
        case .all: "all"
        }
    }
}

/// Export the persistent application logs to a temporary file for sharing.
///
/// Reads the rotating on-disk log written by `PersistentLogStore`, which spans
/// previous app sessions too — unlike the old `OSLogStore(.currentProcessIdentifier)`
/// approach, which only ever saw the current process and lost history on kill.
func generateLogFile(range: LogExportRange) throws -> URL {
    let data = PersistentLogStore.shared.readForExport(since: range.cutoff)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("FurAffinity App Logs (\(range.filenameSuffix)).txt")
    try data.write(to: url)
    return url
}
