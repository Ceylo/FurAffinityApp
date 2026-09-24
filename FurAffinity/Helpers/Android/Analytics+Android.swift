//
//  Analytics+Android.swift
//  FurAffinityUI (Android)
//
//  Native-Swift driver for the Kotlin `FAAnalyticsBridge`, through SkipBridge's
//  `AnyDynamicObject` like `CrashReporting+Android.swift`. The iOS counterpart is
//  the `amplitude` global in FurAffinityApp.swift.
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The JNI inside is
//  `canImport(Android)`-guarded and no-ops on Darwin.
//

import Foundation
#if canImport(Android)
import SkipBridge
#endif

/// Starts Amplitude unless this build carries the placeholder key, and logs which,
/// in the words iOS uses.
func startAnalytics() {
    var started = false
    #if canImport(Android)
    if Secrets.amplitudeApiKey != Secrets.placeholderApiKey {
        do {
            let bridge = try AnyDynamicObject(className: "fur.affinity.ui.FAAnalyticsBridge")
            let confirmed: Bool? = try bridge.start(Secrets.amplitudeApiKey)
            started = confirmed == true
        } catch {
            logger.error("Analytics: could not start FAAnalyticsBridge: \(error)")
        }
    }
    #endif
    logger.info("Amplitude is \(started ? "initialized" : "left uninitialized")")
}
