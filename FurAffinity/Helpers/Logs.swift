//
//  Logs.swift
//  FurAffinity
//
//  Created by Ceylo on 12/10/2022.
//

import Foundation
import OSLog
import FALogging
import Defaults

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

/// Snapshots and diff-logs UserDefaults so state-update logs show only what changed.
enum DefaultsChangeLog {
    /// Current values of every tracked Defaults key, keyed by name.
    static func snapshot() -> [String: Any] {
        let userDefaults = UserDefaults.standard
        var snapshot = [String: Any]()
        for key in Defaults.Keys.all {
            if let value = userDefaults.object(forKey: key.name) {
                snapshot[key.name] = value
            }
        }
        return snapshot
    }

    /// UserDefaults values are property-list objects (NSObject subclasses), so compare via isEqual.
    static func valuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return (lhs as? NSObject)?.isEqual(rhs) ?? false
        default: return false
        }
    }

    /// Logs only the keys that changed between two snapshots (added `+`, removed `-`, changed `~`).
    static func logChanges(from old: [String: Any], to new: [String: Any]) {
        var changes = [String]()
        for key in Set(old.keys).union(new.keys).sorted() {
            let oldValue = old[key]
            let newValue = new[key]
            guard !valuesEqual(oldValue, newValue) else { continue }
            switch (oldValue, newValue) {
            case let (nil, newValue?): changes.append("+ \(key) = \(newValue)")
            case let (oldValue?, nil): changes.append("- \(key) (was \(oldValue))")
            case let (oldValue?, newValue?): changes.append("~ \(key): \(oldValue) → \(newValue)")
            default: break
            }
        }
        guard !changes.isEmpty else { return }
        let separator = changes.count == 1 ? " " : "\n"
        logger.info("UserDefaults state update:\(separator)\(changes.joined(separator: "\n"))")
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
