//
//  AndroidAppStorage.swift
//  FurAffinityUI (Android)
//
//  Lets shared settings screens spell an observable defaults-backed toggle as
//  `@AppStorage(.someKey)` on Android, keeping the key name and default value in
//  `UserDefaultKeys.swift` instead of duplicated as literals.
//
//  Why not a `@Default` shim: `Ceylo/Defaults@android` guards its SwiftUI support
//  behind `#if !os(Android)`, and a re-declared `Default` property wrapper cannot
//  replace it — skipstone recognizes state property wrappers by *attribute name*
//  (`@State`, `@AppStorage`, …) when generating a bridged view's
//  `Java_initState_<name>` / `Java_syncState_<name>` functions. Verified: a custom
//  `@Default` wrapper — even one storing an `AppStorage`, and even declared as
//  `typealias Default = AppStorage` — yields no entry in the generated bridge, so its
//  `BridgedAppStorageBox` never receives a Compose state and the value neither
//  persists nor triggers recomposition. The attribute has to literally read
//  `@AppStorage`.
//
//  So shared screens carry a small `#if os(Android)` block declaring their toggles
//  with `@AppStorage`, and iOS keeps `@Default` unchanged. Bool-only: every settings
//  key those screens read is a Bool.
//

#if os(Android)

import Foundation
import SwiftUI
import Defaults

extension AppStorage where Value == Bool {
    /// Binds to the same `UserDefaults` entry `Defaults[key]` reads elsewhere.
    init(_ key: Defaults.Key<Bool>) {
        self.init(wrappedValue: key.defaultValue, key.name)
    }
}

#endif
