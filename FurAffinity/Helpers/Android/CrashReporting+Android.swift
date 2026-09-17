//
//  CrashReporting+Android.swift
//  FurAffinityUI (Android)
//
//  Native-Swift driver for the Kotlin `FACrashReportingBridge`, through SkipBridge's
//  `AnyDynamicObject` like `ImageFetchBridge`.
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The JNI inside is `canImport(Android)`-guarded and no-ops on Darwin.
//

import Foundation
#if canImport(Android)
import SkipBridge

// `nonisolated(unsafe)`: AnyDynamicObject isn't Sendable but wraps a JNI global
// ref that is safe to read from any thread.
nonisolated(unsafe) private let crashReportingBridge: AnyDynamicObject? = {
    do {
        return try AnyDynamicObject(className: "fur.affinity.ui.FACrashReportingBridge")
    } catch {
        logger.error("CrashReporting: could not create FACrashReportingBridge: \(error)")
        return nil
    }
}()
#endif

func startPlatformCrashReporter(_ configuration: CrashReportingConfiguration) {
    #if canImport(Android)
    let started: Bool? = try? crashReportingBridge?.start(
        configuration.dsn, configuration.release, configuration.environment
    )
    if started != true {
        logger.error("CrashReporting: FACrashReportingBridge.start did not confirm")
    }
    #endif
}

func stopPlatformCrashReporter() {
    #if canImport(Android)
    let _: Bool? = try? crashReportingBridge?.stop()
    #endif
}
