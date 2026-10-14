//
//  LaunchLog.swift
//  FurAffinity
//
//  The first line of every log the app produces, and so the first thing read in any
//  bug report. Shared rather than written twice: version, build configuration and
//  wording have to match across platforms for the two logs to be comparable.
//  Only what genuinely differs is passed in.
//

import Foundation
import FAKit

enum BuildConfiguration: CustomStringConvertible {
    case debug
    case release

    var description: String {
        switch self {
        case .debug:
            "debug"
        case .release:
            "release"
        }
    }
}

#if DEBUG
    let buildConfiguration = BuildConfiguration.debug
#else
    let buildConfiguration = BuildConfiguration.release
#endif

/// - Parameters:
///   - operatingSystem: named by the caller — "iOS 26.5", "Android 17" — since each
///     platform has its own way to ask, and neither reads the other's correctly.
///   - details: appended verbatim. iOS carries its `[CFDIAG] applicationState` here.
func logAppLaunch(operatingSystem: String, details: String = "") {
    let suffix = details.isEmpty ? "" : " \(details)"
    logger.info("Launched FurAffinity \(FAAppVersion.string) on \(operatingSystem), \(buildConfiguration) build\(suffix)")
}
