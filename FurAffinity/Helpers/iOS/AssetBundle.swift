//
//  AssetBundle.swift
//  FurAffinity
//
//  The bundle shared views name when they reach for an asset-catalog image, so an
//  `Image(_:bundle:)` in shared code needs no platform fence. Android re-declares this
//  over its own catalog in Helpers/Android/AssetBundle+Android.swift.
//
//  Spelled `Bundle.faAssets`, not `.faAssets`: SkipSwiftUI's `Image`/`Color` take a
//  `Bundle?`, and implicit member lookup does not reach through the optional there.
//

#if !FA_SKIP_MODULE

import Foundation

extension Bundle {
    /// The bundle carrying `Assets.xcassets`. The Xcode app target has no
    /// `Bundle.module`; the Skip module has no `.main` catalog.
    static var faAssets: Bundle { .main }
}

#endif
