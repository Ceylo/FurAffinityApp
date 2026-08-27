//
//  AssetBundle.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of `FurAffinity/Helpers/iOS/AssetBundle.swift`. Skip mirrors this
//  module's own Assets.xcassets into Android resources, and `Image(_:bundle:)` resolves
//  through it — see Android/docs/assets-and-resources.md.
//
//  Unguarded, like every other substitution file: it must also serve the module's Darwin
//  bridge compile, which excludes the `#if !FA_SKIP_MODULE` iOS half.
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
