//
//  FADefaultsBridge.kt
//  FurAffinity (Android)
//
//  Kotlin half of `Defaults.updates` on Android, reached by class name through
//  AnyDynamicObject like FACoilBridge/FAMediaBridge — see AndroidDefaultsUpdates.swift.
//
//  A listener on the preferences file is the faithful analog of KVO on the suite: every
//  writer lands in `shared_prefs/defaults.xml`, `@AppStorage` included.
//

package fur.affinity.ui

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import skip.foundation.ProcessInfo

class FADefaultsBridge {
    // Boolean, not Unit: AnyDynamicObject can't resolve the void overload.
    fun start(): Boolean = Companion.start()

    companion object {
        private const val TAG = "FADefaultsBridge"

        // SharedPreferences keeps only a *weak* reference to its listener, so one that
        // isn't held here is collected and the stream silently stops firing.
        private var listener: SharedPreferences.OnSharedPreferenceChangeListener? = null

        @Synchronized
        fun start(): Boolean {
            if (listener != null) return true
            return try {
                // "defaults" is SkipFoundation's suite name for UserDefaults.standard.
                val prefs = ProcessInfo.processInfo.androidContext
                    .getSharedPreferences("defaults", Context.MODE_PRIVATE)
                val changeListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
                    if (key != null) {
                        FADefaultsObserver.shared.keyDidChange(key)
                    }
                }
                prefs.registerOnSharedPreferenceChangeListener(changeListener)
                listener = changeListener
                true
            } catch (e: Exception) {
                Log.e(TAG, "could not observe shared preferences", e)
                false
            }
        }
    }
}
