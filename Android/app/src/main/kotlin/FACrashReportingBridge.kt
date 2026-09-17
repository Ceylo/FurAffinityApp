//
//  FACrashReportingBridge.kt
//  FurAffinity (Android)
//
//  Starts sentry-android for CrashReporting+Android.swift, reached by class name
//  through AnyDynamicObject like FAImageFetchBridge. Manifest auto-init is off:
//  Swift decides whether reporting runs (DSN present, setting on).
//
//  Swift crashes are native signals in the app's .so files. Tombstones (collected
//  by the OS out of process) catch them on Android 12+, the NDK signal handler
//  below that. Never both: the SDK fails to merge their two reports of one crash
//  and sends it twice. See docs/crash-reporting.md.
//

package fur.affinity.ui

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.sentry.Sentry
import io.sentry.android.core.SentryAndroid
import skip.foundation.ProcessInfo

class FACrashReportingBridge {
    // Boolean, not Unit: AnyDynamicObject can't resolve the void overload.
    fun start(dsn: String, release: String, environment: String, reportsSinceMillis: Long): Boolean = try {
        SentryAndroid.init(ProcessInfo.processInfo.androidContext) { options ->
            options.dsn = dsn
            options.release = release
            options.environment = environment
            // Without it the tombstone path derives an invalid dist from `release`.
            options.dist = versionCode()
            // Crashes and ANRs only: no identifiers, no captured UI, no tracing.
            options.isSendDefaultPii = false
            options.isAttachScreenshot = false
            options.isAttachViewHierarchy = false
            options.isAnrEnabled = true
            val hasTombstones = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
            options.isTombstoneEnabled = hasTombstones
            options.isEnableNdk = !hasTombstones
            options.addInAppInclude("fur.affinity.ui")
            // The last tombstone and ANR are read back from the OS at start, even
            // when reporting was off at the time; see CrashReportingConfiguration.
            options.setBeforeSend { event, _ ->
                if (event.timestamp.time < reportsSinceMillis) null else event
            }
            options.tracesSampleRate = null
        }
        true
    } catch (e: Exception) {
        Log.e(TAG, "could not start Sentry", e)
        false
    }

    private fun versionCode(): String {
        val context = ProcessInfo.processInfo.androidContext
        return context.packageManager.getPackageInfo(context.packageName, 0).longVersionCode.toString()
    }

    fun stop(): Boolean {
        Sentry.close()
        return true
    }

    fun setTag(key: String, value: String): Boolean {
        Sentry.setTag(key, value)
        return true
    }

    /// Throws on the next main-looper turn: thrown here, inside the JNI call, it
    /// would come back to Swift as an error instead of crashing.
    fun crashTest(): Boolean {
        Handler(Looper.getMainLooper()).post {
            throw IllegalStateException("Crash test") // CRASH-TEST-SITE kotlinException
        }
        return true
    }

    companion object {
        private const val TAG = "FACrashReportingBridge"
    }
}
