//
//  FAOrientationBridge.kt
//  FurAffinity (Android)
//
//  Reached by class name through AnyDynamicObject — see OrientationBridge.swift.
//

package fur.affinity.ui

import android.app.Activity
import android.content.pm.ActivityInfo
import skip.ui.UIApplication

class FAOrientationBridge {
    fun allowLandscape(allowed: Boolean) {
        allowsLandscape = allowed
        val activity = UIApplication.shared.androidActivity ?: return
        activity.runOnUiThread { apply(activity) }
    }

    companion object {
        @Volatile private var allowsLandscape = false

        fun apply(activity: Activity) {
            val isPhone = activity.resources.configuration.smallestScreenWidthDp < 600
            activity.requestedOrientation = if (isPhone && !allowsLandscape) {
                ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            } else {
                ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            }
        }
    }
}
