//
//  FurAffinityUIRoot.swift
//  FurAffinityUI (Android)
//
//  Entry point of the Skip Fuse app. Android-only: an `Android/` directory is
//  not part of the iOS Xcode target, so nothing here affects the iOS build.
//  The Skip target compiles FurAffinity/ directly; anything it must not build
//  carries `#if !FA_SKIP_MODULE`.
//

import Foundation
import Defaults
import FAKit
import FALogging
import SkipFuse
import SwiftUI

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
        // Both must land before anything reads them, and the loggers freeze their
        // subsystem on first use — so this is the very first thing the app does.
        // `Bundle.main` has no Info.plist behind it in a native Skip module, and its
        // bundleIdentifier names the Skip module rather than the install.
        FALogSubsystem.override = AndroidAppInfo.packageName
        FAAppVersion.override = AndroidAppInfo.versionName
        // FAKit owns the web layer but not the two Kotlin bridges behind it. Here
        // rather than in a `.task`: both are read as a view is *constructed*.
        FAWebViewUserAgent.platformProvider = { AndroidAppInfo.webViewDefaultUserAgent }
        FAWebSession.imageCredentialsSink = { userAgent, cookieHeader in
            CoilImageLoader.configure(userAgent: userAgent, cookie: cookieHeader)
        }
        // Page fetches join the image layer's connection pool. FAKit gains no JNI:
        // the transport is a struct of closures the app module fills in.
        FAWebSession.nativeTransport = OkHttpTransport.transport
        // The counterpart of FurAffinityApp.init()'s line, same shared format.
        logAppLaunch(
            operatingSystem: AndroidAppInfo.operatingSystem,
            details: "debuggable=\(AndroidAppInfo.isDebuggable)"
        )
        // Before any `Defaults.Key` is created: a key captures its suite and registers
        // its default value at construction, so one touched earlier lands in the orphan
        // store.
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
        // Android's "entered the background", the same moment Kingfisher sweeps its
        // disk cache on iOS — and off the launch path, which is why not onLaunch.
        Task { await FAImageStore.shared.pruneStagedMedia() }
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
