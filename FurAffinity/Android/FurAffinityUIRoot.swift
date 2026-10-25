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
    private let foreground = ForegroundState()

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
        BackgroundRefreshManager.registerNotificationCategories()
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

    /// From `FABackgroundRefreshJobService`. Stands down while an activity is in the
    /// foreground, where iOS never runs its BGAppRefreshTask: the user is seeing the
    /// content, and `backgroundRefreshLifecycle()` is advancing the watermarks. An
    /// activity resuming mid-run cancels it, as iOS expires its task. `conditions` is
    /// logged with each run.
    /* SKIP @bridge */public func performBackgroundRefresh(_ conditions: String, respectingBudget: Bool) async {
        let refresh: Task<Void, any Error>
        switch foreground.startBackgroundWork({
            Task { try await BackgroundRefreshManager.performFetchAndNotify(respectingBudget: respectingBudget) }
        }) {
        case .started(let work):
            refresh = work
        case .inForeground:
            logger.info("Skipping background refresh: the app is in the foreground (\(conditions))")
            return
        case .alreadyRunning:
            logger.info("Skipping background refresh: a run is already in progress (\(conditions))")
            return
        }
        logger.info("Background refresh run started (\(conditions))")
        let start = ContinuousClock.now
        defer {
            logger.info("Background refresh run ended after \(ContinuousClock.now - start)")
            foreground.endBackgroundWork()
            // A process the job started never reaches `onStop`, where they're pruned otherwise.
            Task { await FAImageStore.shared.performingFileIO { pruneMediaCopies() } }
        }
        do {
            try await refresh.value
        } catch {
            logger.error("Background refresh failed: \(error)")
        }
    }

    /// From `FABackgroundRefreshJobService`, once a scheduled run is over.
    /* SKIP @bridge */public func scheduleBackgroundRefresh() {
        BackgroundRefreshManager.schedule()
    }

    /// From `FABackgroundRefreshJobService.onStopJob`: the system took the job back.
    /* SKIP @bridge */public func cancelBackgroundRefresh() {
        logger.info("Background refresh stopped by the system")
        foreground.cancelBackgroundWork()
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
        foreground.enter()
    }

    /* SKIP @bridge */public func onPause() {
        logger.debug("onPause")
    }

    /* SKIP @bridge */public func onStop() {
        logger.debug("onStop")
        foreground.leave()
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

/// Whether an activity is in the foreground, which the activity callbacks write, and the
/// background refresh running meanwhile, which entering the foreground cancels.
private final class ForegroundState: @unchecked Sendable {
    private let lock = NSLock()
    private var isInForeground = false
    private var backgroundWork: Task<Void, any Error>?

    func enter() {
        lock.withLock { isInForeground = true }
        cancelBackgroundWork()
    }

    func cancelBackgroundWork() {
        lock.withLock { backgroundWork }?.cancel()
    }

    func leave() {
        lock.withLock { isInForeground = false }
    }

    enum Start {
        case started(Task<Void, any Error>)
        case inForeground
        case alreadyRunning
    }

    /// Starts and records the work `start` returns, unless an activity is in the foreground
    /// or earlier work is still running, which `enter()` must remain able to cancel.
    func startBackgroundWork(_ start: () -> Task<Void, any Error>) -> Start {
        lock.withLock {
            if isInForeground { return .inForeground }
            if backgroundWork != nil { return .alreadyRunning }
            let work = start()
            backgroundWork = work
            return .started(work)
        }
    }

    func endBackgroundWork() {
        lock.withLock { backgroundWork = nil }
    }
}
