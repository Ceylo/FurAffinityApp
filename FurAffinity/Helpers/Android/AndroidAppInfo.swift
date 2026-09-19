//
//  AndroidAppInfo.swift
//  FurAffinityUI (Android)
//
//  Native-Swift driver for the Kotlin `FAAppInfoBridge`: the package name, the app
//  version and commit, whether this build is debuggable, and the stock WebView User-Agent. Same
//  `AnyDynamicObject` reflection as `ImageFetchBridge` — FurAffinityUI is a native
//  Skip module and can't `import android.*`.
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The JNI inside is `canImport(Android)`-guarded and no-ops on Darwin.
//

import Foundation
import FAKit
#if canImport(Android)
import SkipBridge
#endif

enum AndroidAppInfo {
    #if canImport(Android)
    // `nonisolated(unsafe)`: AnyDynamicObject isn't Sendable but wraps a JNI global
    // ref that is safe to read from any thread.
    nonisolated(unsafe) private static let bridge: AnyDynamicObject? = {
        do {
            return try AnyDynamicObject(className: "fur.affinity.ui.FAAppInfoBridge")
        } catch {
            logger.error("AndroidAppInfo: could not create FAAppInfoBridge: \(error)")
            return nil
        }
    }()
    #endif

    /// The installed applicationId, or nil off Android. `Bundle.main.bundleIdentifier`
    /// is nil in a plain SwiftPM module here and names the Skip module rather than the
    /// install in the bridged one, so this is the only accurate source.
    static let packageName: String? = {
        #if canImport(Android)
        guard let bridge else { return nil }
        do {
            let name: String? = try bridge.packageName()
            return (name?.isEmpty ?? true) ? nil : name
        } catch {
            logger.error("AndroidAppInfo.packageName threw: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }()

    /// The installed app's `versionName` (Skip.env's MARKETING_VERSION), or nil off
    /// Android. `Bundle.main.infoDictionary` is empty in a native Skip module, so
    /// this is the only version source the app has.
    static let versionName: String? = {
        #if canImport(Android)
        guard let bridge else { return nil }
        do {
            let name: String? = try bridge.versionName()
            return (name?.isEmpty ?? true) ? nil : name
        } catch {
            logger.error("AndroidAppInfo.versionName threw: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }()

    /// The short git hash the APK was built from, or nil when the build couldn't read
    /// it or off Android.
    static let commit: String? = {
        #if canImport(Android)
        guard let bridge else { return nil }
        do {
            let commit: String? = try bridge.commit()
            return (commit?.isEmpty ?? true) ? nil : commit
        } catch {
            logger.error("AndroidAppInfo.commit threw: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }()

    /// Whether this build carries `android:debuggable`. False off Android and
    /// whenever the bridge is unreachable, so a development-only affordance stays
    /// hidden rather than leaking into a release.
    static let isDebuggable: Bool = {
        #if canImport(Android)
        guard let bridge else { return false }
        do {
            let debuggable: Bool? = try bridge.isDebuggable()
            return debuggable ?? false
        } catch {
            logger.error("AndroidAppInfo.isDebuggable threw: \(error)")
            return false
        }
        #else
        return false
        #endif
    }()

    /// The OS as the launch log names it, e.g. "Android 17".
    static let operatingSystem: String = {
        #if canImport(Android)
        guard let bridge else { return "Android" }
        do {
            let release: String? = try bridge.osRelease()
            return (release?.isEmpty ?? true) ? "Android" : "Android \(release!)"
        } catch {
            logger.error("AndroidAppInfo.osRelease threw: \(error)")
            return "Android"
        }
        #else
        return "Android"
        #endif
    }()

    /// The WebView's stock User-Agent, before any override.
    static let webViewDefaultUserAgent: String? = {
        #if canImport(Android)
        guard let bridge else { return nil }
        do {
            let userAgent: String? = try bridge.defaultUserAgent()
            return (userAgent?.isEmpty ?? true) ? nil : userAgent
        } catch {
            logger.error("AndroidAppInfo.defaultUserAgent threw: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }()
}
