//
//  Colors.swift
//  FurAffinityUI (Android)
//
//  The colorsets shared views reach for by name. Each single-sources the iOS entry
//  through a symlinked `Contents.json` (see Android/docs/assets-and-resources.md §Sharing asset-catalog
//  entries) — only `bundle:` differs from the iOS declarations.
//

import SwiftUI

extension Color {
    /// The shared `BorderOverlay` colorset (black @0.1 light / white @0.2 dark).
    static let borderOverlay = Color("BorderOverlay", bundle: Bundle.faAssets)
    /// The shared `ButtonBorderOverlay` colorset (opaque black light / white dark).
    static let buttonBorderOverlay = Color("ButtonBorderOverlay", bundle: Bundle.faAssets)
}
