//
//  AssetBundle.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of `FurAffinity/Helpers/iOS/AssetBundle.swift`. Skip mirrors this
//  module's own Assets.xcassets into Android resources, and `Image(_:bundle:)` resolves
//  through it — see Android/docs/assets-and-resources.md.
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The Darwin bridge compile
//  excludes the `#if !FA_SKIP_MODULE` iOS half, so this is the only declaration there.
//
//  Spelled `Bundle.faAssets`, not `.faAssets`: SkipSwiftUI's `Image`/`Color` take a
//  `Bundle?`, and implicit member lookup does not reach through the optional there.
//

import Foundation

extension Bundle {
    /// The bundle carrying `Assets.xcassets`. The Xcode app target has no
    /// `Bundle.module`; the Skip module has no `.main` catalog.
    static var faAssets: Bundle { .module }
}
