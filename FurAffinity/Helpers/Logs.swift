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

/// Export the persistent application logs to a temporary file for sharing.
///
/// Reads the rotating on-disk log written by `PersistentLogStore`, which spans
/// previous app sessions too — unlike the old `OSLogStore(.currentProcessIdentifier)`
/// approach, which only ever saw the current process and lost history on kill.
func generateLogFile() throws -> URL {
    let data = PersistentLogStore.shared.readAllForExport()
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("FurAffinity App Logs.txt")
    try data.write(to: url)
    return url
}
