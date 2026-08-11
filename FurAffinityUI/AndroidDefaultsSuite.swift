//
//  AndroidDefaultsSuite.swift
//  FurAffinityUI (Android)
//
//  Points `Defaults` at the store the rest of the app uses.
//
//  On Android `UserDefaults.standard` means two different things. In a module Skip
//  processes, skipstone emits `typealias UserDefaults = AndroidUserDefaults`, so
//  `.standard` is the app's `SharedPreferences` (`shared_prefs/defaults.xml`) — where
//  `@AppStorage`/`@Default` and raw `UserDefaults` writes land. The `Defaults` package
//  is a plain SwiftPM dependency compiled untouched, so *its* `.standard` is
//  Foundation's own instance: a separate store nothing else reads, and one that never
//  reaches disk here. That is why `Defaults[key] = value` read back fine yet vanished.
//
//  `Ceylo/Defaults@android` exposes `Defaults.defaultSuite` for this. It has to be set
//  before the first key is created — a key captures its suite and registers its default
//  value into it right away — hence `Application.onCreate` → `onInit()`, which runs
//  before any view or `Model` exists.
//

import Foundation
import Defaults

/// Installs the shared-preferences-backed suite as the one `Defaults` keys use.
func installDefaultsSuite() {
    #if os(Android)
    Defaults.defaultSuite = UserDefaults.standard
    #endif
}
