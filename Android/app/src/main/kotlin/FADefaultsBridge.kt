//
//  FADefaultsBridge.kt
//  FurAffinity (Android)
//
//  Kotlin half of `Defaults.updates` on Android. Same shape and rationale as
//  FACoilBridge/FAMediaBridge: FurAffinityUI is a *native* Skip module and cannot touch
//  Android framework classes directly, so it reaches this one by class name through
//  SkipBridge's AnyDynamicObject — see AndroidDefaultsUpdates.swift.
//
//  Defaults' own observation layer is ObjC KVO on the suite, which Android's Swift has
//  no runtime for. An OnSharedPreferenceChangeListener on the same preferences file is
//  the faithful analog: it sees *every* writer — `Defaults[…]`, `@AppStorage`, raw
//  `UserDefaults` — because they all land in `shared_prefs/defaults.xml`.
//

package fur.affinity.ui

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import skip.foundation.ProcessInfo

class FADefaultsBridge {
    // Returns a value (not Unit) so the Swift AnyDynamicObject call resolves to a typed
    // overload instead of the ambiguous void one.
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
