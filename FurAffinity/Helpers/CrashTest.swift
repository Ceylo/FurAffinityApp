//
//  CrashTest.swift
//  FurAffinity
//
//  Deliberate crashes that prove a report arrives symbolicated, driven by
//  Scripts/check-crash-reporting.sh. Each crash sits on a line marked
//  `CRASH-TEST-SITE <case>`, which the script greps for the expected line number.
//
//  Armed only from outside the UI: launch arguments on iOS, intent extras on a
//  non-release Android build. See Android/docs/crash-reporting.md.
//

import Foundation
import Defaults
import FAKit

enum CrashTestCase: String, CaseIterable {
    case swiftFatalError
    case swiftForceUnwrapFAKit
    case swiftBackgroundThread
    /// Android only: a Kotlin exception, which proves the R8 mapping upload.
    case kotlinException
    /// iOS only: a 5 s main-thread hang, reported as a non-fatal event — the path
    /// that picks up contexts a crash does not.
    case appHang
}

enum CrashTest {
    /// Writes the crash-reporting setting from outside the UI, for the checker's
    /// opt-out control. A launch argument can't do it: `-crashReportingEnabled NO`
    /// lands in the argument domain as the *string* "NO", which `Defaults` ignores.
    /// Call before `CrashReporting.start`, which reads the setting.
    static func applyReportingOverride(_ value: String?) {
        guard let value else { return }
        let enabled = (value as NSString).boolValue
        Defaults[.crashReportingEnabled] = enabled
        CrashReporting.settingChanged(enabled: enabled)
    }

    /// Tags the report with `crash_test_run=<runID>` so the script finds this exact
    /// event, then crashes once the reporter has settled.
    static func run(_ name: String, runID: String) {
        guard let testCase = CrashTestCase(rawValue: name) else {
            logger.error("Unknown crash test \(name)")
            return
        }
        logger.warning("Crash test \(name) (run \(runID)) in 2 s")
        setPlatformCrashReporterTag("crash_test_run", runID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            switch testCase {
            case .swiftFatalError:
                swiftFatalError()
            case .swiftForceUnwrapFAKit:
                _ = CrashTestSite.forceUnwrapNil(nil)
            case .swiftBackgroundThread:
                Thread.detachNewThread { swiftBackgroundThread(runID.count) }
            case .kotlinException:
                crashPlatformReporterInKotlin()
            case .appHang:
                appHang()
            }
        }
    }

    @inline(never)
    static func swiftFatalError() {
        fatalError("Crash test") // CRASH-TEST-SITE swiftFatalError
    }

    /// Logs after sleeping: a sleep in tail position leaves no frame of its own.
    @inline(never)
    static func appHang() {
        Thread.sleep(forTimeInterval: 5) // CRASH-TEST-SITE appHang
        logger.info("Crash test appHang is over")
    }

    @inline(never)
    static func swiftBackgroundThread(_ index: Int) {
        let empty = [Int]()
        _ = empty[index] // CRASH-TEST-SITE swiftBackgroundThread
    }
}
