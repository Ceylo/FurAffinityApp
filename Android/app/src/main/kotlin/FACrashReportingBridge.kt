//
//  FACrashReportingBridge.kt
//  FurAffinity (Android)
//
//  Starts sentry-android for CrashReporting+Android.swift, reached by class name
//  through AnyDynamicObject like FAImageFetchBridge. Manifest auto-init is off:
//  Swift decides whether reporting runs (DSN present, setting on).
//
//  Swift crashes are native signals in the app's .so files. Two integrations
//  catch them: tombstones (Android 12+, collected by the OS out of process) and
//  the NDK signal handler as the fallback below 12. See docs/crash-reporting.md.
//

package fur.affinity.ui

import android.util.Log
import io.sentry.Sentry
import io.sentry.android.core.SentryAndroid
import skip.foundation.ProcessInfo

class FACrashReportingBridge {
    // Boolean, not Unit: AnyDynamicObject can't resolve the void overload.
    fun start(dsn: String, release: String, environment: String): Boolean = try {
        SentryAndroid.init(ProcessInfo.processInfo.androidContext) { options ->
            options.dsn = dsn
            options.release = release
            options.environment = environment
            // Crashes and ANRs only: no identifiers, no captured UI, no tracing.
            options.isSendDefaultPii = false
            options.isAttachScreenshot = false
            options.isAttachViewHierarchy = false
            options.isAnrEnabled = true
            options.isEnableNdk = true
            options.isTombstoneEnabled = true
            options.tracesSampleRate = null
        }
        true
    } catch (e: Exception) {
        Log.e(TAG, "could not start Sentry", e)
        false
    }

    fun stop(): Boolean {
        Sentry.close()
        return true
    }

    companion object {
        private const val TAG = "FACrashReportingBridge"
    }
}
