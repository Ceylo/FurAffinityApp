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
import Kingfisher
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

    /// Between the activity's `onResume` and `onStop`.
    private let isInForeground = LockedFlag()

    private init() {
    }

    /* SKIP @bridge */public func onInit() {
        // These must land before anything reads them, and the loggers freeze their
        // subsystem on first use — so this is the very first thing the app does.
        // `Bundle.main` has no Info.plist behind it in a native Skip module, and its
        // bundleIdentifier names the Skip module rather than the install.
        FALogSubsystem.override = AndroidAppInfo.packageName
        FAAppVersion.override = AndroidAppInfo.versionName
        FAAppVersion.commitOverride = AndroidAppInfo.commit
        // FAKit owns the web layer but not the two Kotlin bridges behind it. Here
        // rather than in a `.task`: both are read as a view is *constructed*.
        FAWebViewUserAgent.platformProvider = { AndroidAppInfo.webViewDefaultUserAgent }
        FAWebSession.imageCredentialsSink = { userAgent, cookieHeader in
            ImageFetchBridge.configure(userAgent: userAgent, cookie: cookieHeader)
        }
        // Page fetches join the image layer's connection pool. FAKit gains no JNI:
        // the transport is a struct of closures the app module fills in.
        FAWebSession.nativeTransport = OkHttpTransport.transport
        // The background refresh's session, built where no WebView may be mounted.
        FAWebSession.cookieJarHeaderProvider = { await cookieJarHeader(for: $0) }
        // Picks the light or dark FA theme rich text is styled after.
        FATheme.currentProvider = { AndroidAppInfo.isNightMode ? .dark : .light }
        // The counterpart of FurAffinityApp.init()'s line, same shared format.
        logAppLaunch(
            operatingSystem: AndroidAppInfo.operatingSystem,
            details: "debuggable=\(AndroidAppInfo.isDebuggable)"
        )
        // Before the first image load; Kingfisher's own default bounds nothing here.
        configureImageCacheForAndroid()
        // Before any `Defaults.Key` is created: a key captures its suite and registers
        // its default value at construction, so one touched earlier lands in the orphan
        // store.
        installDefaultsSuite()
        // As early as it can be: it reads a Defaults key, so not before the suite.
        CrashReporting.start(appID: AndroidAppInfo.packageName)
        // Where FurAffinityApp.init() starts it on iOS: after crash reporting.
        startAnalytics()
        // Matches FurAffinityApp.init() on iOS. A no-op on a fresh Android install
        // (see Defaults.startingSchemaVersion), but it stamps the schema version so a
        // later migration knows where to resume.
        Defaults.runSettingsMigrations()
        // As FurAffinityApp.init() on iOS. SkipUI holds a tap that launched the app until then.
        UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
    }

    /// From `MainActivity`'s intent extras on a non-release build; see
    /// Scripts/check-crash-reporting.sh.
    /* SKIP @bridge */public func runCrashTest(_ name: String, _ runID: String) {
        CrashTest.run(name, runID: runID)
    }

    /// From `MainActivity`'s `faOpenURL` extra on a non-release build.
    /* SKIP @bridge */public func openDebugURL(_ url: String) {
        Task { @MainActor in
            NotificationCoordinator.shared.setPendingDeepLink(fromURLString: url)
        }
    }

    /// From `FABackgroundRefreshWorker`. Stands down while an activity is in the
    /// foreground, where iOS never runs its BGAppRefreshTask: the user is seeing the
    /// content, and `backgroundRefreshLifecycle()` is advancing the watermarks.
    /* SKIP @bridge */public func performBackgroundRefresh() async -> Bool {
        guard !isInForeground.value else {
            logger.info("Skipping background refresh: the app is in the foreground")
            return true
        }
        do {
            try await BackgroundRefreshManager.performFetchAndNotify()
            return !Task.isCancelled
        } catch {
            logger.error("Background refresh failed: \(error)")
            return false
        }
    }

    /// Lets the script's opt-out control flip the setting without the UI.
    /* SKIP @bridge */public func setCrashReportingEnabled(_ enabled: Bool) {
        Defaults[.crashReportingEnabled] = enabled
        CrashReporting.settingChanged(enabled: enabled)
    }

    /* SKIP @bridge */public func onLaunch() {
        logger.debug("onLaunch")
    }

    /* SKIP @bridge */public func onResume() {
        logger.debug("onResume")
        isInForeground.value = true
    }

    /* SKIP @bridge */public func onPause() {
        logger.debug("onPause")
    }

    /* SKIP @bridge */public func onStop() {
        logger.debug("onStop")
        isInForeground.value = false
        // Android's "entered the background", the same moment Kingfisher sweeps its
        // disk cache on iOS — and off the launch path, which is why not onLaunch. iOS
        // gets this from `UIApplicationDidEnterBackground`, which `ImageCache` cannot
        // observe here.
        ImageCache.default.cleanExpiredDiskCache()
        // Save/Share copies. `tmp/` is `cacheDir` here, which nothing else empties.
        // Through the store's gate, since `Task.detached` would block the
        // cooperative pool.
        Task { await FAImageStore.shared.performingFileIO { pruneMediaCopies() } }
    }

    /* SKIP @bridge */public func onDestroy() {
        logger.debug("onDestroy")
    }

    /* SKIP @bridge */public func onLowMemory() {
        logger.debug("onLowMemory")
        // Decoded images are the app's largest reclaimable allocation; the disk cache
        // behind them is untouched, so this only costs a re-decode.
        ImageCache.default.clearMemoryCache()
    }
}

/// A Bool the activity callbacks write and the background worker reads.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
