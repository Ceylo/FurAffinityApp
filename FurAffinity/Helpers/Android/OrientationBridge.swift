//
//  OrientationBridge.swift
//  FurAffinityUI (Android)
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The JNI inside is
//  `canImport(Android)`-guarded and no-ops on Darwin.
//

import Foundation
#if canImport(Android)
import SkipBridge
#endif

enum OrientationBridge {
    #if canImport(Android)
    // `nonisolated(unsafe)`: AnyDynamicObject isn't Sendable but wraps a JNI global
    // ref that is safe to read from any thread.
    nonisolated(unsafe) private static let bridge: AnyDynamicObject? = {
        do {
            return try AnyDynamicObject(className: "fur.affinity.ui.FAOrientationBridge")
        } catch {
            logger.error("OrientationBridge: could not create FAOrientationBridge: \(error)")
            return nil
        }
    }()
    #endif

    static func allowLandscape(_ allowed: Bool) {
        #if canImport(Android)
        guard isJNIInitialized, let bridge else { return }
        do {
            let _: Void = try bridge.allowLandscape(allowed)
        } catch {
            logger.error("OrientationBridge.allowLandscape threw: \(error)")
        }
        #endif
    }
}
