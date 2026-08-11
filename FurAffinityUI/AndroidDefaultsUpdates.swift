//
//  AndroidDefaultsUpdates.swift
//  FurAffinityUI (Android)
//
//  `Defaults.updates` for Android. The fork guards the upstream implementation out
//  because it is ObjC KVO on the suite (`DefaultsObservation` calls
//  `addObserver(_:forKeyPath:options:context:)`) and Android's Swift has no ObjC
//  runtime — so the name is free here, and the app module, which links CJNI, declares
//  it. Reaching Android APIs from the fork itself is the shape that fails with
//  "missing required module CJNI"; the same reasoning as AndroidDefault.swift.
//
//  The mechanism is an `OnSharedPreferenceChangeListener` on `shared_prefs/defaults.xml`
//  (FADefaultsBridge.kt), which is the faithful analog of KVO on the suite: every
//  writer lands in that one file — `Defaults[…]` (see AndroidDefaultsSuite.swift),
//  `@Default`/`@AppStorage`, raw `UserDefaults`.
//
//  Two differences from KVO worth knowing:
//  - SharedPreferences fires only when a value actually *changes*, while KVO fires on
//    every set. Benign for every current observer, arguably better.
//  - The callback arrives on whichever thread committed the edit, which is fine for
//    yielding to a continuation.
//
//  `#if os(Android)` is correct here, unlike the substitution files: the module's
//  Darwin bridge compile resolves the real `Defaults.updates`, and defining ours there
//  would collide.
//

#if os(Android)

import Foundation
import SkipBridge
import Defaults

/// Sink for the Kotlin listener. Bridged so `FADefaultsBridge` can call it by name,
/// the way `Main.kt` calls `FurAffinityUIAppDelegate`.
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
    /// Only this overload is implemented — it is the only one shared code calls. The
    /// single-key and variadic forms stay unavailable rather than speculative.
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

/// Fans a changed key name out to every stream watching it.
///
/// `nonisolated(unsafe)` behind an `NSLock`, as the other JNI-backed globals in this
/// module do: the Kotlin callback can arrive on any thread.
private enum DefaultsUpdateRegistry {
    private struct Registration {
        let keyNames: Set<String>
        let continuation: AsyncStream<Void>.Continuation
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var registrations = [Int: Registration]()
    nonisolated(unsafe) private static var lastID = 0
    /// Handle on the Kotlin listener's owner, created on the first observation so
    /// nothing is registered in an app that never observes.
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
