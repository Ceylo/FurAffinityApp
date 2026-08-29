//
//  AndroidDefault.swift
//  FurAffinityUI (Android)
//
//  Defaults' `@Default` for Android. `Ceylo/Defaults@android` guards its SwiftUI
//  support behind `#if !os(Android)`, so the name is free here, and declaring it in the
//  app module (which does link CJNI) lets shared screens write `@Default(.someKey)`
//  exactly as they do on iOS, with no `#if`.
//
//  `#if os(Android)` is correct here, unlike the other substitution files: the Darwin
//  bridge compile of this module resolves `Default` from the real Defaults package.
//
//  It cannot be `@AppStorage`, and it cannot delegate to one: skipstone matches state
//  property wrappers by *attribute name* and is a closed binary, so a wrapper of our
//  own gets no generated bridge and never receives a Compose state. What it can do is
//  own the box itself — `BridgedAppStorageBox`, `Java_initStateSupport()` and
//  `Binding(appStorageBox:)` are all public skip-fuse-ui API, and the bridge's
//  `rememberSaveable` only supplies lifetime, which a static box per key gives just as
//  well for process-lived app settings. Reading it during body evaluation still reads
//  the Compose `MutableState`, which is what registers the recomposition dependency.
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
