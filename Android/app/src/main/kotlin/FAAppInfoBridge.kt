//
//  FAAppInfoBridge.kt
//  FurAffinity (Android)
//
//  Facts about the installed app that native Swift can't reach, exposed by
//  class name through AnyDynamicObject like FAImageFetchBridge/FADefaultsBridge — see
//  AndroidAppInfo.swift.
//
//  `Bundle.main` in a Skip Fuse *native* module is swift-corelibs-foundation's,
//  backed by no Info.plist, so its infoDictionary is empty: the version has to come
//  from the package manager instead.
//

package fur.affinity.ui

import android.content.pm.ApplicationInfo
import android.util.Log
import android.webkit.WebSettings
import skip.foundation.ProcessInfo

class FAAppInfoBridge {
    private val context get() = ProcessInfo.processInfo.androidContext

    /// The installed applicationId — Skip.env's PRODUCT_BUNDLE_IDENTIFIER plus the
    /// per-worktree suffix a debug build adds (see build.gradle.kts).
    fun packageName(): String = context.packageName

    /// `versionName` as installed, i.e. Skip.env's MARKETING_VERSION.
    fun versionName(): String = try {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: ""
    } catch (e: Exception) {
        Log.e(TAG, "could not read the package version", e)
        ""
    }

    /// Whether this build is debuggable. Broader than BuildConfig.DEBUG: it also
    /// covers a release build deliberately marked debuggable.
    fun isDebuggable(): Boolean =
        (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    /// The Android release version, e.g. "17". `ProcessInfo` can't answer this: it
    /// reports the Linux kernel, not the Android release.
    fun osRelease(): String = android.os.Build.VERSION.RELEASE ?: ""

    /// The stock WebView User-Agent, before any customUserAgent override. Reading
    /// it needs no WebView instance, so it is safe at any point in startup.
    fun defaultUserAgent(): String = try {
        WebSettings.getDefaultUserAgent(context)
    } catch (e: Exception) {
        Log.e(TAG, "could not read the default WebView user agent", e)
        ""
    }

    companion object {
        private const val TAG = "FAAppInfoBridge"
    }
}
