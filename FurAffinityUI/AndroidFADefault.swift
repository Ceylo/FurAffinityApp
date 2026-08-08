//
//  AndroidFADefault.swift
//  FurAffinityUI (Android)
//
//  Android's `@FADefault`, the app's own defaults-backed property wrapper. iOS aliases
//  it to Defaults' `@Default` (FurAffinity/Helpers/FADefault.swift); this is the
//  Android implementation, so shared settings screens declare a toggle once with no
//  `#if`.
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
//  Bool-only: every settings key the ported screens read is a Bool.
//

#if os(Android)

import Foundation
import SkipSwiftUI
import Defaults

@propertyWrapper
struct FADefault {
    private let storage: AppStorage<Bool>

    init(_ key: Defaults.Key<Bool>) {
        storage = FADefaultStorage.storage(for: key)
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
private enum FADefaultStorage {
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

#else

// The module's Darwin bridge compile has the real Defaults, same as iOS.
import Defaults

typealias FADefault = Default

#endif
