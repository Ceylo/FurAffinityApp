//
//  AndroidDefaultsSuite.swift
//  FurAffinityUI (Android)
//
//  Points `Defaults` at the store the rest of the app uses. `UserDefaults.standard`
//  means two different things on Android — see Android/README.md §Defaults.
//

import Foundation
import Defaults

/// Installs the shared-preferences-backed suite as the one `Defaults` keys use.
///
/// Must run before the first key is created, since a key captures its suite and
/// registers its default value into it right away.
func installDefaultsSuite() {
    #if os(Android)
    Defaults.defaultSuite = UserDefaults.standard
    #endif
}
