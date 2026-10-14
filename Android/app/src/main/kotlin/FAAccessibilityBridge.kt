//
//  FAAccessibilityBridge.kt
//  FurAffinity (Android)
//
//  Accessibility settings native Swift can't reach, exposed by class name through
//  AnyDynamicObject like FAAppInfoBridge — see AndroidAccessibility.swift.
//

package fur.affinity.ui

import android.content.Context
import android.os.Build
import android.view.accessibility.AccessibilityManager
import skip.foundation.ProcessInfo

class FAAccessibilityBridge {
    /// `originalMillis` raised to the user's "Time to take action" for text with
    /// controls, as Compose's `calculateRecommendedTimeoutMillis` does for a snackbar:
    /// before Q, "indefinite" (`Int.MAX_VALUE`) while touch exploration is on.
    fun recommendedTimeoutMillis(originalMillis: Long): Long {
        val manager = ProcessInfo.processInfo.androidContext
            .getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
            ?: return originalMillis
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return if (manager.isTouchExplorationEnabled) Int.MAX_VALUE.toLong() else originalMillis
        }
        val flags = AccessibilityManager.FLAG_CONTENT_TEXT or AccessibilityManager.FLAG_CONTENT_CONTROLS
        return manager.getRecommendedTimeoutMillis(
            originalMillis.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(), flags
        ).toLong()
    }
}
