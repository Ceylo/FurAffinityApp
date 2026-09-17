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
    /// Events from before this are dropped. Android reports the OS's record of the
    /// last native crash (its tombstone) and of the last ANR at the next start,
    /// whether or not reporting was on when they happened.
    var reportsSince: Date

    /// Nil when there is nothing to report to: a placeholder DSN (every build but a
    /// distributed one), or the user turned reporting off.
    static func make(
        dsn: String,
        appID: String?,
        version: String,
        configuration: BuildConfiguration,
        enabled: Bool,
        enabledSince: Date
    ) -> CrashReportingConfiguration? {
        guard enabled, dsn != CrashReportingSecrets.placeholderDSN, !dsn.isEmpty else {
            return nil
        }
        return CrashReportingConfiguration(
            dsn: dsn,
            release: "\(appID ?? "FurAffinity")@\(version)",
            environment: configuration.description,
            reportsSince: enabledSince
        )
    }
}

enum CrashReporting {
    /// Starts the reporter if the build has a DSN and the user hasn't opted out.
    /// On Android, call only after `installDefaultsSuite()`.
    static func start(appID: String?) {
        // The first start with reporting on counts as switching it on.
        if Defaults[.crashReportingEnabled], Defaults[.crashReportingEnabledSince] == 0 {
            Defaults[.crashReportingEnabledSince] = Date().timeIntervalSince1970
        }
        guard let configuration = CrashReportingConfiguration.make(
            dsn: CrashReportingSecrets.dsn,
            appID: appID,
            version: FAAppVersion.string,
            configuration: buildConfiguration,
            enabled: Defaults[.crashReportingEnabled],
            enabledSince: Date(timeIntervalSince1970: Defaults[.crashReportingEnabledSince])
        ) else {
            logger.info("Crash reporting is off")
            return
        }
        startPlatformCrashReporter(configuration)
        logger.info("Crash reporting started for \(configuration.release) (\(configuration.environment))")
    }

    /// Applies a change of the setting, already written. Turning it off stops
    /// reporting at once; turning it on takes effect at the next launch, and nothing
    /// that crashed before now is ever sent.
    static func settingChanged(enabled: Bool) {
        if enabled {
            Defaults[.crashReportingEnabledSince] = Date().timeIntervalSince1970
            logger.info("Crash reporting turned on, from the next launch")
        } else {
            stopPlatformCrashReporter()
            logger.info("Crash reporting turned off")
        }
    }
}
