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
import io.sentry.protocol.App
import io.sentry.protocol.Contexts
import io.sentry.protocol.Device
import io.sentry.protocol.OperatingSystem
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
            // Its answer would be dropped in beforeSend anyway; don't probe for su.
            options.isEnableRootCheck = false
            // Nothing sent without a crash, and nothing in a report but the crash:
            // no session per launch, no breadcrumbs (UI, lifecycle, system, network).
            options.isEnableAutoSessionTracking = false
            options.enableAllAutoBreadcrumbs(false)
            options.maxBreadcrumbs = 0
            options.isAnrEnabled = true
            val hasTombstones = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
            options.isTombstoneEnabled = hasTombstones
            options.isEnableNdk = !hasTombstones
            options.addInAppInclude("fur.affinity.ui")
            // The last tombstone and ANR are read back from the OS at start, even
            // when reporting was off at the time; see CrashReportingConfiguration.
            options.setBeforeSend { event, _ ->
                if (event.timestamp.time < reportsSinceMillis) null
                else event.also { keepListedContextOnly(it.contexts) }
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
        private val KEPT_CONTEXTS = setOf("os", "trace", "device", "app")

        /// The contexts the privacy policy covers, so nothing an SDK adds ever
        /// leaves: `trace` (random ids) whole, the OS, device and app copied field
        /// by field — versions, model, the install id. Dropped: any other context,
        /// root status, and the device's timezone, locale, connectivity, battery,
        /// free memory and storage, boot time, granted permissions, screen names.
        private fun keepListedContextOnly(contexts: Contexts) {
            for (key in java.util.Collections.list(contexts.keys())) {
                if (key !in KEPT_CONTEXTS) contexts.remove(key)
            }
            contexts.operatingSystem?.let { os ->
                contexts.setOperatingSystem(OperatingSystem().also {
                    it.name = os.name
                    it.version = os.version
                    it.build = os.build
                    it.kernelVersion = os.kernelVersion
                })
            }
            contexts.device?.let { d ->
                contexts.setDevice(Device().also {
                    it.id = d.id
                    it.manufacturer = d.manufacturer
                    it.brand = d.brand
                    it.family = d.family
                    it.model = d.model
                    it.modelId = d.modelId
                    it.archs = d.archs
                    it.isSimulator = d.isSimulator
                    it.chipset = d.chipset
                    it.cpuDescription = d.cpuDescription
                    it.processorCount = d.processorCount
                    it.processorFrequency = d.processorFrequency
                    it.memorySize = d.memorySize
                    it.storageSize = d.storageSize
                    it.screenWidthPixels = d.screenWidthPixels
                    it.screenHeightPixels = d.screenHeightPixels
                    it.screenDensity = d.screenDensity
                    it.screenDpi = d.screenDpi
                })
            }
            contexts.app?.let { a ->
                contexts.setApp(App().also {
                    it.appIdentifier = a.appIdentifier
                    it.appName = a.appName
                    it.appVersion = a.appVersion
                    it.appBuild = a.appBuild
                    it.buildType = a.buildType
                    it.appStartTime = a.appStartTime
                    it.startType = a.startType
                    it.inForeground = a.inForeground
                    it.splitApks = a.splitApks
                    it.splitNames = a.splitNames
                })
            }
        }
    }
}
