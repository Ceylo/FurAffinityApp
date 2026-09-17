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
import FAKit

enum CrashTestCase: String, CaseIterable {
    case swiftFatalError
    case swiftForceUnwrapFAKit
    case swiftBackgroundThread
    /// Android only: a Kotlin exception, which proves the R8 mapping upload.
    case kotlinException
}

enum CrashTest {
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
            }
        }
    }

    @inline(never)
    static func swiftFatalError() {
        fatalError("Crash test") // CRASH-TEST-SITE swiftFatalError
    }

    @inline(never)
    static func swiftBackgroundThread(_ index: Int) {
        let empty = [Int]()
        _ = empty[index] // CRASH-TEST-SITE swiftBackgroundThread
    }
}
