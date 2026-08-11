//
//  AndroidDefault.swift
//  FurAffinityUI (Android)
//
//  Defaults' `@Default` for Android. `Ceylo/Defaults@android` guards its SwiftUI
//  support behind `#if !os(Android)` — importing SwiftUI (→ SkipUI → CJNI) from a plain
//  SwiftPM package breaks the Skip build — so the name is free here, and declaring it
//  in the app module (which does link CJNI) lets shared screens write
//  `@Default(.someKey)` exactly as they do on iOS, with no `#if`.
//
//  `#if os(Android)` is correct here, unlike the other substitution files: the Darwin
//  bridge compile of this module resolves `Default` from the real Defaults package.
//
//  Why this can't just be `@AppStorage`: skipstone recognizes state property wrappers
//  by *attribute name* and generates each bridged view's `Java_initState_<name>` from
//  it, so a wrapper of our own gets no bridge — its `BridgedAppStorageBox` never
//  receives a Compose state, and the value neither persists nor recomposes. skipstone
//  is a closed binary, so that list can't be extended.
//
//  What it can do instead is own the box itself. The pieces skipstone's generated code
//  uses — `BridgedAppStorageBox`, `Java_initStateSupport()`, `Binding(appStorageBox:)`
//  — are all public API of skip-fuse-ui, and the generated `rememberSaveable` only
//  provides *lifetime*: it keeps one support object alive across recompositions. App
//  settings are global and process-lived, so a static box per defaults key serves the
//  same purpose. Reading it during body evaluation still reads the Compose
//  `MutableState` inside the composition, which is what registers the recomposition
//  dependency.
//
//  Reactivity matches iOS: `AppStorageSupport` registers a SharedPreferences change
//  listener, so a write from anywhere — not just this wrapper — updates every view
//  showing the key. Verified on the emulator.
//
//  Bool-only: every settings key the ported screens read is a Bool.
//

#if os(Android)

import Foundation
import SkipSwiftUI
import Defaults

@propertyWrapper
struct Default {
    private let storage: AppStorage<Bool>

    init(_ key: Defaults.Key<Bool>) {
        storage = DefaultStorage.storage(for: key)
    }

    var wrappedValue: Bool {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Bool> {
        storage.projectedValue
    }
}

/// One Compose-backed storage per defaults key, kept for the process lifetime — the
/// role skipstone's generated `rememberSaveable` plays for a bridged `@AppStorage`. A
/// fresh one per view instantiation would mean a fresh `MutableState` on every body
/// evaluation, which no composition would ever observe changing.
///
/// `AppStorage` is a struct over a reference-type box, so copies of a cached value all
/// read and write the same state.
private enum DefaultStorage {
    nonisolated(unsafe) private static var storages = [String: AppStorage<Bool>]()
    private static let lock = NSLock()

    static func storage(for key: Defaults.Key<Bool>) -> AppStorage<Bool> {
        lock.lock()
        defer { lock.unlock() }
        if let existing = storages[key.name] {
            return existing
        }
        let storage = AppStorage(wrappedValue: key.defaultValue, key.name)
        // Creates the AppStorageSupport and registers it with StateTracking, which
        // defers the actual Compose state creation to the next body boundary. Without
        // it the box stays unbacked: no persistence and no recomposition.
        _ = storage.projectedValue.appStorageBox!.Java_initStateSupport()
        storages[key.name] = storage
        return storage
    }
}

#endif
