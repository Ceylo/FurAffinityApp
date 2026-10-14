//
//  AndroidAccessibility.swift
//  FurAffinityUI (Android)
//
//  Native-Swift driver for the Kotlin `FAAccessibilityBridge`, through the same
//  `AnyDynamicObject` reflection as `AndroidAppInfo`.
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The JNI inside is
//  `canImport(Android)`-guarded and no-ops on Darwin.
//

import Foundation
#if canImport(Android)
import SkipBridge
#endif

enum AndroidAccessibility {
    #if canImport(Android)
    // `nonisolated(unsafe)`: AnyDynamicObject isn't Sendable but wraps a JNI global
    // ref that is safe to read from any thread.
    nonisolated(unsafe) private static let bridge: AnyDynamicObject? = {
        do {
            return try AnyDynamicObject(className: "fur.affinity.ui.FAAccessibilityBridge")
        } catch {
            logger.error("AndroidAccessibility: could not create FAAccessibilityBridge: \(error)")
            return nil
        }
    }()
    #endif

    /// `timeout` for text with controls, raised to the user's "Time to take action"
    /// setting. Read on each call: the setting can change while the app runs.
    static func recommendedTimeout(_ timeout: Duration) -> Duration {
        #if canImport(Android)
        guard let bridge else { return timeout }
        do {
            let millis = Int64(timeout / .milliseconds(1))
            let recommended: Int64? = try bridge.recommendedTimeoutMillis(millis)
            return recommended.map { .milliseconds($0) } ?? timeout
        } catch {
            logger.error("AndroidAccessibility.recommendedTimeoutMillis threw: \(error)")
            return timeout
        }
        #else
        return timeout
        #endif
    }
}
