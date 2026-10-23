//
//  FANotificationBridge.kt
//  FurAffinity (Android)
//
//  What the background refresh needs from the Android framework: scheduling its
//  WorkManager job, and blurring a mature thumbnail on the CPU. Called from Swift by
//  class name through SkipBridge's AnyDynamicObject, like FAMediaBridge — see
//  BackgroundRefreshManager+Android.swift and ImageBlur+Android.swift.
//

package fur.affinity.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit
import kotlin.math.max
import kotlin.math.roundToInt
import skip.foundation.ProcessInfo

class FANotificationBridge {
    // Boolean, not Unit: AnyDynamicObject can't resolve the void overload.
    fun scheduleBackgroundRefresh(intervalMinutes: Long): Boolean = Companion.scheduleBackgroundRefresh(intervalMinutes)

    fun blur(inputPath: String, outputPath: String, radius: Double): Boolean = Companion.blur(inputPath, outputPath, radius)

    companion object {
        private const val TAG = "FANotificationBridge"
        private const val WORK_NAME = "fa.background-refresh"
        /// The blur runs on a bitmap this many times smaller (a power of two, for `inSampleSize`).
        private const val DOWNSCALE = 4
        private val NETWORK_REQUIRED = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

        /// UPDATE keeps the running schedule, so calling this on every trip to the
        /// background doesn't push the next run further out.
        fun scheduleBackgroundRefresh(intervalMinutes: Long): Boolean = try {
            val request = PeriodicWorkRequestBuilder<FABackgroundRefreshWorker>(intervalMinutes, TimeUnit.MINUTES)
                .setConstraints(NETWORK_REQUIRED)
                .build()
            WorkManager.getInstance(ProcessInfo.processInfo.androidContext)
                .enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
            true
        } catch (e: Exception) {
            Log.e(TAG, "scheduleBackgroundRefresh failed: $e")
            false
        }

        /// A one-off run of the same worker, for testing: WorkManager won't force a
        /// periodic run before its period has elapsed. MainActivity's debug extras. Same
        /// constraint as the periodic job, so it runs under the same conditions.
        fun runBackgroundRefresh(delaySeconds: Long) {
            val request = OneTimeWorkRequestBuilder<FABackgroundRefreshWorker>()
                .setConstraints(NETWORK_REQUIRED)
                .setInitialDelay(delaySeconds, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(ProcessInfo.processInfo.androidContext).enqueue(request)
        }

        /// Writes a JPEG of the image at `inputPath` blurred about as Kingfisher's
        /// `blurred(withRadius:)` does on iOS, whose radius is the Gaussian's sigma: three
        /// box passes of that radius approximate it, run on a copy decoded downscaled. Only
        /// the collapsed thumbnail shows it, so it is written at that size.
        fun blur(inputPath: String, outputPath: String, radius: Double): Boolean = try {
            val options = BitmapFactory.Options().apply { inSampleSize = DOWNSCALE }
            val small = BitmapFactory.decodeFile(inputPath, options) ?: throw IllegalArgumentException("undecodable image")
            val width = small.width
            val height = small.height
            val pixels = IntArray(width * height)
            small.getPixels(pixels, 0, width, 0, 0, width, height)
            val boxRadius = max(1, (radius / DOWNSCALE).roundToInt())
            repeat(3) {
                boxBlur(pixels, width, height, boxRadius, horizontal = true)
                boxBlur(pixels, width, height, boxRadius, horizontal = false)
            }
            val blurred = Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
            FileOutputStream(outputPath).use { blurred.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        } catch (e: Exception) {
            Log.e(TAG, "blur failed: $e")
            false
        }

        /// One sliding-window box blur along rows or columns, edges clamped.
        private fun boxBlur(pixels: IntArray, width: Int, height: Int, radius: Int, horizontal: Boolean) {
            val length = if (horizontal) width else height
            val lines = if (horizontal) height else width
            val line = IntArray(length)
            val window = 2 * radius + 1
            for (l in 0 until lines) {
                fun index(i: Int) = if (horizontal) l * width + i else i * width + l
                for (i in 0 until length) line[i] = pixels[index(i)]
                var a = 0; var r = 0; var g = 0; var b = 0
                for (k in -radius..radius) {
                    val p = line[k.coerceIn(0, length - 1)]
                    a += p ushr 24; r += (p shr 16) and 0xFF; g += (p shr 8) and 0xFF; b += p and 0xFF
                }
                for (i in 0 until length) {
                    pixels[index(i)] = ((a / window) shl 24) or ((r / window) shl 16) or ((g / window) shl 8) or (b / window)
                    val out = line[(i - radius).coerceIn(0, length - 1)]
                    val into = line[(i + radius + 1).coerceIn(0, length - 1)]
                    a += (into ushr 24) - (out ushr 24)
                    r += ((into shr 16) and 0xFF) - ((out shr 16) and 0xFF)
                    g += ((into shr 8) and 0xFF) - ((out shr 8) and 0xFF)
                    b += (into and 0xFF) - (out and 0xFF)
                }
            }
        }
    }
}
