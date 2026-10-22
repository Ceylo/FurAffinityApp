//
//  BridgeCall.swift
//  FurAffinityUI (Android)
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The JNI inside is `canImport(Android)`-guarded.
//

import Foundation
#if canImport(Android)
import SkipBridge

/// Calls the Kotlin class `fur.affinity.ui.<className>` through `body`, on a global
/// queue: these calls block, so they must not run on the cooperative pool. Returns
/// `fallback` when the class can't be reached or the call throws.
func callBridgeOffPool<T: Sendable>(
    _ className: String,
    qos: DispatchQoS.QoSClass = .utility,
    fallback: T,
    _ body: @escaping @Sendable (AnyDynamicObject) throws -> T
) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: qos).async {
            do {
                continuation.resume(returning: try body(AnyDynamicObject(className: "fur.affinity.ui.\(className)")))
            } catch {
                logger.error("Could not call \(className): \(error)")
                continuation.resume(returning: fallback)
            }
        }
    }
}
#endif
