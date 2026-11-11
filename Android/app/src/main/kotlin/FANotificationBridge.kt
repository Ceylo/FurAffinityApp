//
//  FANotificationBridge.kt
//  FurAffinity (Android)
//
//  What the background refresh needs from the Android framework: scheduling its
//  JobScheduler job, and blurring a mature thumbnail on the CPU. Called from Swift by
//  class name through SkipBridge's AnyDynamicObject, like FAMediaBridge — see
//  BackgroundRefreshManager+Android.swift and ImageBlur+Android.swift.
//

package fur.affinity.ui

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.PowerManager
import android.util.Log
import java.io.FileOutputStream
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.concurrent.TimeUnit
import kotlin.math.max
import kotlin.math.roundToInt
import skip.foundation.ProcessInfo

class FANotificationBridge {
    // Boolean, not Unit: AnyDynamicObject can't resolve the void overload.
    fun scheduleBackgroundRefresh(delaySeconds: Long): Boolean = Companion.scheduleBackgroundRefresh(delaySeconds)

    fun blur(inputPath: String, outputPath: String, radius: Double): Boolean = Companion.blur(inputPath, outputPath, radius)

    fun schedulingDiagnostics(): String = Companion.schedulingDiagnostics()

    companion object {
        private const val TAG = "FANotificationBridge"
        /// Far from WorkManager's ids, which count up from 0 on API < 34, where it has no namespace.
        const val SCHEDULED_JOB_ID = 0x46410001
        private const val DEBUG_JOB_ID = 0x46410002
        /// The blur runs on a bitmap this many times smaller (a power of two, for `inSampleSize`).
        private const val DOWNSCALE = 4

        private val context get() = ProcessInfo.processInfo.androidContext
        private val scheduler get() = context.getSystemService(JobScheduler::class.java)
        private fun job(id: Int) = JobInfo.Builder(id, ComponentName(context, FABackgroundRefreshJobService::class.java))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)

        /// Replaces the pending run, and stops a running one: call it after `jobFinished`.
        fun scheduleBackgroundRefresh(delaySeconds: Long): Boolean = try {
            val latency = TimeUnit.SECONDS.toMillis(delaySeconds)
            scheduler.schedule(job(SCHEDULED_JOB_ID).setMinimumLatency(latency).setPersisted(true).build()) == JobScheduler.RESULT_SUCCESS
        } catch (e: Exception) {
            Log.e(TAG, "scheduleBackgroundRefresh failed: $e")
            false
        }

        /// An extra run, for testing: MainActivity's debug extras. Same network requirement
        /// as the scheduled job, so it runs under the same conditions.
        fun runBackgroundRefresh(delaySeconds: Long) {
            val result = scheduler.schedule(job(DEBUG_JOB_ID).setMinimumLatency(TimeUnit.SECONDS.toMillis(delaySeconds)).build())
            if (result != JobScheduler.RESULT_SUCCESS) Log.e(TAG, "runBackgroundRefresh: scheduling failed")
        }

        fun schedulingDiagnostics(): String {
            val now = System.currentTimeMillis()
            val prefs = context.getSharedPreferences("fa.background-refresh.diagnostics", Context.MODE_PRIVATE)
            val since = prefs.getLong("lastDump", now - TimeUnit.DAYS.toMillis(1))
            prefs.edit().putLong("lastDump", now).apply()
            val parts = listOf(
                probe("pending") { pendingState() },
                probe("reason history") { reasonHistory(since) },
                probe("bucket changes") { bucketChanges(since, now) },
                probe("exits") { exits(since) },
                probe("background restricted") { "${context.getSystemService(ActivityManager::class.java).isBackgroundRestricted}" },
                probe("battery optimization exempt") {
                    "${context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)}"
                },
            )
            return parts.joinToString(", ")
        }

        private fun probe(name: String, body: () -> String): String = try {
            "$name: ${body()}"
        } catch (e: Exception) {
            "$name: <$e>"
        }

        private fun pendingState(): String {
            if (scheduler.getPendingJob(SCHEDULED_JOB_ID) == null) return "none"
            return when {
                Build.VERSION.SDK_INT >= 36 -> scheduler.getPendingJobReasons(SCHEDULED_JOB_ID).joinToString("+") { pendingReason(it) }
                Build.VERSION.SDK_INT >= 34 -> pendingReason(scheduler.getPendingJobReason(SCHEDULED_JOB_ID))
                else -> "yes"
            }
        }

        private fun reasonHistory(since: Long): String {
            if (Build.VERSION.SDK_INT < 36) return "n/a"
            // A finished job's history goes with it.
            if (scheduler.getPendingJob(SCHEDULED_JOB_ID) == null) return "none"
            return scheduler.getPendingJobReasonsHistory(SCHEDULED_JOB_ID)
                .filter { it.timestampMillis >= since }
                .joinToString(" ", "[", "]") { "${time(it.timestampMillis)} ${it.pendingJobReasons.joinToString("+") { r -> pendingReason(r) }}" }
        }

        private fun bucketChanges(since: Long, now: Long): String {
            val events = context.getSystemService(UsageStatsManager::class.java).queryEventsForSelf(since, now)
            val changes = mutableListOf<String>()
            val event = UsageEvents.Event()
            while (events.getNextEvent(event)) {
                if (event.eventType == UsageEvents.Event.STANDBY_BUCKET_CHANGED) {
                    changes += "${time(event.timeStamp)} ${bucket(event.appStandbyBucket)}"
                }
            }
            return changes.joinToString(" ", "[", "]")
        }

        private fun exits(since: Long): String {
            if (Build.VERSION.SDK_INT < 30) return "n/a"
            return context.getSystemService(ActivityManager::class.java)
                .getHistoricalProcessExitReasons(context.packageName, 0, 5)
                .filter { it.timestamp >= since }
                .joinToString(" ", "[", "]") { "${time(it.timestamp)} ${exitReason(it.reason)} (${it.description})" }
        }

        private fun time(millis: Long) = Instant.ofEpochMilli(millis).truncatedTo(ChronoUnit.SECONDS).toString()

        fun bucket(raw: Int?): String = when (raw) {
            UsageStatsManager.STANDBY_BUCKET_ACTIVE -> "active"
            UsageStatsManager.STANDBY_BUCKET_WORKING_SET -> "working set"
            UsageStatsManager.STANDBY_BUCKET_FREQUENT -> "frequent"
            UsageStatsManager.STANDBY_BUCKET_RARE -> "rare"
            UsageStatsManager.STANDBY_BUCKET_RESTRICTED -> "restricted"
            else -> "$raw"
        }

        private fun pendingReason(reason: Int): String = when (reason) {
            JobScheduler.PENDING_JOB_REASON_EXECUTING -> "executing"
            JobScheduler.PENDING_JOB_REASON_UNDEFINED -> "undefined"
            JobScheduler.PENDING_JOB_REASON_APP -> "app"
            JobScheduler.PENDING_JOB_REASON_APP_STANDBY -> "app standby"
            JobScheduler.PENDING_JOB_REASON_BACKGROUND_RESTRICTION -> "background restriction"
            JobScheduler.PENDING_JOB_REASON_CONSTRAINT_CONNECTIVITY -> "connectivity"
            JobScheduler.PENDING_JOB_REASON_CONSTRAINT_MINIMUM_LATENCY -> "minimum latency"
            JobScheduler.PENDING_JOB_REASON_DEVICE_STATE -> "device state"
            JobScheduler.PENDING_JOB_REASON_JOB_SCHEDULER_OPTIMIZATION -> "scheduler optimization"
            JobScheduler.PENDING_JOB_REASON_QUOTA -> "quota"
            JobScheduler.PENDING_JOB_REASON_USER -> "user"
            else -> "$reason"
        }

        private fun exitReason(reason: Int): String = when (reason) {
            ApplicationExitInfo.REASON_LOW_MEMORY -> "low memory"
            ApplicationExitInfo.REASON_USER_REQUESTED -> "user requested"
            ApplicationExitInfo.REASON_USER_STOPPED -> "user stopped"
            ApplicationExitInfo.REASON_OTHER -> "other"
            ApplicationExitInfo.REASON_SIGNALED -> "signaled"
            ApplicationExitInfo.REASON_FREEZER -> "freezer"
            ApplicationExitInfo.REASON_CRASH -> "crash"
            ApplicationExitInfo.REASON_ANR -> "anr"
            else -> "$reason"
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
