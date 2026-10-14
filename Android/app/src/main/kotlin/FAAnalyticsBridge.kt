//
//  FAAnalyticsBridge.kt
//  FurAffinity (Android)
//
//  Starts Amplitude for Analytics+Android.swift, reached by class name through
//  AnyDynamicObject like FACrashReportingBridge. Mirrors the iOS configuration in
//  FurAffinityApp.swift: sessions and app lifecycle only, no location, carrier or
//  device identifiers.
//

package fur.affinity.ui

import android.content.pm.ApplicationInfo
import android.util.Log
import com.amplitude.android.Amplitude
import com.amplitude.android.AutocaptureOption
import com.amplitude.android.Configuration
import com.amplitude.android.TrackingOptions
import com.amplitude.common.Logger
import skip.foundation.ProcessInfo

class FAAnalyticsBridge {
    // Boolean, not Unit: AnyDynamicObject can't resolve the void overload.
    fun start(apiKey: String, commit: String): Boolean = try {
        val context = ProcessInfo.processInfo.androidContext
        // ADID is the advertising id, app set id the IDFV analogue iOS disables.
        val trackingOptions = TrackingOptions()
            .disableCity()
            .disableRegion()
            .disableCarrier()
            .disableDma()
            .disableIpAddress()
            .disableAdid()
            .disableAppSetId()
            .disableLatLng()
        amplitude = Amplitude(
            Configuration(
                apiKey = apiKey,
                context = context,
                trackingOptions = trackingOptions,
                autocapture = setOf(AutocaptureOption.SESSIONS, AutocaptureOption.APP_LIFECYCLES),
                // The defaults already, stated so the device id stays a random one and
                // no location is read even if a permission ever arrives.
                useAdvertisingIdForDeviceId = false,
                useAppSetIdForDeviceId = false,
                locationListening = false,
            )
        ).also {
            if ((context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
                it.logger.logMode = Logger.LogMode.DEBUG
            }
            // A user property, as on iOS: tells a test build's events from a release's.
            if (commit.isNotEmpty()) it.identify(mapOf("commit" to commit))
        }
        true
    } catch (e: Exception) {
        Log.e(TAG, "could not start Amplitude", e)
        false
    }

    companion object {
        private const val TAG = "FAAnalyticsBridge"
        /// Held for the process lifetime, as the iOS instance is.
        private var amplitude: Amplitude? = null
    }
}
