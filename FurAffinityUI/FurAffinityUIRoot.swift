//
//  FurAffinityUIRoot.swift
//  FurAffinityUI (Android)
//
//  Entry point of the Skip Fuse app. Android-only: this directory is not part of
//  the iOS Xcode target, so nothing here affects the iOS build. Shared iOS
//  sources are pulled in as symlinks under FurAffinityUI/Shared/ as they're
//  ported.
//

import Foundation
import Defaults
import FAKit
import SkipFuse
import SwiftUI

// `logger` now comes from the shared Shared/Logs.swift.

/// The shared top-level view, loaded from the platform-specific app delegates below.
/* SKIP @bridge */public struct FurAffinityUIRootView: View {
    /* SKIP @bridge */public init() {
    }

    public var body: some View {
        AndroidRootView()
    }
}

/// Global application delegate functions.
/* SKIP @bridge */public final class FurAffinityUIAppDelegate: Sendable {
    /* SKIP @bridge */public static let shared = FurAffinityUIAppDelegate()

    private init() {
    }

    /* SKIP @bridge */public func onInit() {
        // Before anything reads a version: `Bundle.main` has no Info.plist behind it
        // in a native Skip module, so without this both the FA User-Agent suffix and
        // the update check read "unknown".
        FAAppVersion.override = AndroidAppInfo.versionName
        // The counterpart of FurAffinityApp.init()'s line, same shared format.
        logAppLaunch(
            operatingSystem: AndroidAppInfo.operatingSystem,
            details: "debuggable=\(AndroidAppInfo.isDebuggable)"
        )
        // Must come first: a `Defaults.Key` captures its suite and registers its
        // default value when it's created, so anything that touches a key before this
        // lands in the orphan store.
        installDefaultsSuite()
        // Matches FurAffinityApp.init() on iOS. A no-op on a fresh Android install
        // (see Defaults.startingSchemaVersion), but it stamps the schema version so a
        // later migration knows where to resume.
        Defaults.runSettingsMigrations()
    }

    /* SKIP @bridge */public func onLaunch() {
        logger.debug("onLaunch")
    }

    /* SKIP @bridge */public func onResume() {
        logger.debug("onResume")
    }

    /* SKIP @bridge */public func onPause() {
        logger.debug("onPause")
    }

    /* SKIP @bridge */public func onStop() {
        logger.debug("onStop")
    }

    /* SKIP @bridge */public func onDestroy() {
        logger.debug("onDestroy")
    }

    /* SKIP @bridge */public func onLowMemory() {
        logger.debug("onLowMemory")
        // Decoded images are the app's largest reclaimable allocation; the disk cache
        // behind them is untouched, so this only costs a re-decode.
        FAImageStore.shared.clearMemoryCache()
    }
}
