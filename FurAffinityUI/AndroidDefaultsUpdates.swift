//
//  AndroidDefaultsUpdates.swift
//  FurAffinityUI (Android)
//
//  `Defaults.updates` for Android, over FADefaultsBridge.kt's SharedPreferences
//  listener. The fork's own implementation is ObjC KVO, which Android has no runtime
//  for, so it leaves the name free for the app module to declare — like
//  AndroidDefault.swift. Unlike KVO, the listener fires only on an actual value change,
//  and from whichever thread committed the edit.
//

#if os(Android)

import Foundation
import SkipBridge
import Defaults

/// Sink for the Kotlin listener, bridged so it can be called by name.
/* SKIP @bridge */public final class FADefaultsObserver: Sendable {
    /* SKIP @bridge */public static let shared = FADefaultsObserver()

    private init() {}

    /* SKIP @bridge */public func keyDidChange(_ name: String) {
        DefaultsUpdateRegistry.keyDidChange(name)
    }
}

extension Defaults {
    /// Observe updates to multiple stored values, without receiving the values.
    ///
    /// The only overload shared code calls, so the only one implemented.
    public static func updates(
        _ keys: [Defaults._AnyKey],
        initial: Bool = true
    ) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = DefaultsUpdateRegistry.add(
                keyNames: Set(keys.map(\.name)),
                continuation: continuation
            )
            continuation.onTermination = { _ in
                DefaultsUpdateRegistry.remove(id)
            }
            if initial {
                continuation.yield()
            }
        }
    }
}

/// Fans a changed key name out to every stream watching it. Locked, since the Kotlin
/// callback can arrive on any thread.
private enum DefaultsUpdateRegistry {
    private struct Registration {
        let keyNames: Set<String>
        let continuation: AsyncStream<Void>.Continuation
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var registrations = [Int: Registration]()
    nonisolated(unsafe) private static var lastID = 0
    /// Created on the first observation, so an app that never observes registers nothing.
    nonisolated(unsafe) private static var bridge: AnyDynamicObject?

    static func add(keyNames: Set<String>, continuation: AsyncStream<Void>.Continuation) -> Int {
        lock.lock()
        defer { lock.unlock() }
        lastID += 1
        registrations[lastID] = Registration(keyNames: keyNames, continuation: continuation)
        startListening()
        return lastID
    }

    static func remove(_ id: Int) {
        lock.lock()
        defer { lock.unlock() }
        registrations[id] = nil
    }

    static func keyDidChange(_ name: String) {
        lock.lock()
        let continuations = registrations.values
            .filter { $0.keyNames.contains(name) }
            .map(\.continuation)
        lock.unlock()

        for continuation in continuations {
            continuation.yield()
        }
    }

    /// Called with `lock` held.
    private static func startListening() {
        guard bridge == nil else { return }
        do {
            let bridge = try AnyDynamicObject(className: "fur.affinity.ui.FADefaultsBridge")
            let ok: Bool? = try bridge.start()
            if ok != true {
                logger.error("FADefaultsBridge.start did not confirm")
            }
            Self.bridge = bridge
        } catch {
            logger.error("Defaults.updates: could not create FADefaultsBridge: \(error)")
        }
    }
}

#endif
