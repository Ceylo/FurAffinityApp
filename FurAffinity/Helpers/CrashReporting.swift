//
//  CrashReporting.swift
//  FurAffinity
//
//  Sentry crash reporting, configured once for both platforms. Each platform only
//  supplies `startPlatformCrashReporter(_:)` / `stopPlatformCrashReporter()`:
//  sentry-cocoa on iOS, sentry-android (with its NDK layer for Swift frames) on
//  Android. See Android/docs/crash-reporting.md.
//

import Foundation
import Defaults
import FAKit

struct CrashReportingConfiguration: Equatable {
    var dsn: String
    /// `<app id>@<version>`, the release the uploaded symbols are matched against.
    var release: String
    var environment: String

    /// Nil when there is nothing to report to: a placeholder DSN (every build but a
    /// distributed one), or the user turned reporting off.
    static func make(
        dsn: String,
        appID: String?,
        version: String,
        configuration: BuildConfiguration,
        enabled: Bool
    ) -> CrashReportingConfiguration? {
        guard enabled, dsn != CrashReportingSecrets.placeholderDSN, !dsn.isEmpty else {
            return nil
        }
        return CrashReportingConfiguration(
            dsn: dsn,
            release: "\(appID ?? "FurAffinity")@\(version)",
            environment: configuration.description
        )
    }
}

enum CrashReporting {
    /// Starts the reporter if the build has a DSN and the user hasn't opted out.
    /// On Android, call only after `installDefaultsSuite()`.
    static func start(appID: String?) {
        guard let configuration = CrashReportingConfiguration.make(
            dsn: CrashReportingSecrets.dsn,
            appID: appID,
            version: FAAppVersion.string,
            configuration: buildConfiguration,
            enabled: Defaults[.crashReportingEnabled]
        ) else {
            logger.info("Crash reporting is off")
            return
        }
        startPlatformCrashReporter(configuration)
        logger.info("Crash reporting started for \(configuration.release) (\(configuration.environment))")
    }

    /// Stops reporting for the rest of this launch; the setting keeps it off afterwards.
    static func stop() {
        stopPlatformCrashReporter()
        logger.info("Crash reporting stopped")
    }
}
