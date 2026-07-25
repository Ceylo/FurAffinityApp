//
//  FACookieBridge.kt
//  FurAffinity (Android)
//
//  Kotlin helper for dropping the WebView's cookies at logout. skip-web exposes
//  `clearCookies()` on `WebViewNavigator`, but only while a WebView is mounted and
//  bound to it — Settings runs long after the login screen is gone — so logout goes
//  straight to the process-wide `CookieManager` instead.
//
//  Called from Swift by class name through SkipBridge's AnyDynamicObject; lives in the
//  app Gradle module for the same reason FACoilBridge does. See AndroidLoginCookies.swift.
//

package fur.affinity.ui

import android.util.Log
import android.webkit.CookieManager

class FACookieBridge {
    // Returns a value (not Unit) so the Swift AnyDynamicObject call resolves to a typed
    // overload instead of the ambiguous void one.
    fun clearCookies(): Boolean = Companion.clearCookies()

    companion object {
        private const val TAG = "FACookieBridge"

        fun clearCookies(): Boolean {
            return try {
                val manager = CookieManager.getInstance()
                manager.removeAllCookies(null)
                // removeAllCookies is asynchronous; flush persists what it has done so
                // the next process start doesn't resurrect the session cookies.
                manager.flush()
                true
            } catch (e: Exception) {
                Log.e(TAG, "clearCookies failed: $e")
                false
            }
        }
    }
}
