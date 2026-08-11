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

import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.CookieManager
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class FACookieBridge {
    // Returns a value (not Unit) so the Swift AnyDynamicObject call resolves to a typed
    // overload instead of the ambiguous void one.
    fun clearCookies(): Boolean = Companion.clearCookies()

    companion object {
        private const val TAG = "FACookieBridge"
        private const val REMOVAL_TIMEOUT_SECONDS = 5L

        // Removes every cookie and waits for the removal to land, so a caller that
        // reopens the login page right after can't be signed back in by a survivor.
        // Returns false if the removal timed out or threw.
        //
        // Must NOT be called from the main thread: `removeAllCookies` needs a running
        // Looper (it throws otherwise), so the call is posted to the main one — and the
        // callback comes back on it. Waiting for the latch there would deadlock.
        fun clearCookies(): Boolean {
            if (Looper.myLooper() == Looper.getMainLooper()) {
                Log.e(TAG, "clearCookies called on the main thread; refusing to deadlock")
                return false
            }

            return try {
                val manager = CookieManager.getInstance()
                val latch = CountDownLatch(1)
                Handler(Looper.getMainLooper()).post {
                    manager.removeAllCookies { latch.countDown() }
                }
                val completed = latch.await(REMOVAL_TIMEOUT_SECONDS, TimeUnit.SECONDS)
                if (!completed) {
                    Log.e(TAG, "clearCookies timed out after ${REMOVAL_TIMEOUT_SECONDS}s")
                }
                // Persist what the removal has done so the next process start doesn't
                // resurrect the session cookies.
                manager.flush()
                completed
            } catch (e: Exception) {
                Log.e(TAG, "clearCookies failed: $e")
                false
            }
        }
    }
}
