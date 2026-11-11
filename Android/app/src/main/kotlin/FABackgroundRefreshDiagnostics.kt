//
//  FABackgroundRefreshDiagnostics.kt
//  FurAffinity (Android)
//

package fur.affinity.ui

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.PowerManager
import java.lang.reflect.Modifier
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.concurrent.TimeUnit
import skip.foundation.ProcessInfo

object FABackgroundRefreshDiagnostics {
    private val context get() = ProcessInfo.processInfo.androidContext
    private const val JOB_ID = FANotificationBridge.SCHEDULED_JOB_ID

    fun dump(): String {
        val now = System.currentTimeMillis()
        val prefs = context.getSharedPreferences("fa.background-refresh.diagnostics", Context.MODE_PRIVATE)
        val since = prefs.getLong("lastDump", now - TimeUnit.DAYS.toMillis(1))
        prefs.edit().putLong("lastDump", now).apply()
        val activity = context.getSystemService(ActivityManager::class.java)
        return listOf(
            probe("pending") { pending(since) },
            probe("bucket changes") { bucketChanges(since, now) },
            probe("exits") { exits(activity, since) },
            probe("background restricted") { "${activity.isBackgroundRestricted}" },
            probe("battery optimization exempt") {
                "${context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)}"
            },
        ).joinToString(", ")
    }

    fun network(): String = probe("network") {
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
        val type = when {
            capabilities == null -> "none"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            else -> "other"
        }
        "$type, validated: ${capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true}"
    }

    fun bucket(raw: Int?): String = raw?.let { constantName(UsageStatsManager::class.java, "STANDBY_BUCKET_", it) } ?: "null"

    fun stopReason(params: JobParameters): String =
        if (Build.VERSION.SDK_INT >= 31) constantName(JobParameters::class.java, "STOP_REASON_", params.stopReason) else "unknown"

    private fun probe(name: String, body: () -> String): String = try {
        "$name: ${body()}"
    } catch (e: Exception) {
        "$name: <$e>"
    }

    /// The current reasons, then their history: a finished job's history goes with it.
    private fun pending(since: Long): String {
        val scheduler = context.getSystemService(JobScheduler::class.java)
        if (scheduler.getPendingJob(JOB_ID) == null) return "none"
        fun reasons(raw: IntArray) = raw.joinToString("+") { pendingReason(it) }
        return when {
            Build.VERSION.SDK_INT >= 36 -> reasons(scheduler.getPendingJobReasons(JOB_ID)) + ", reason history: " +
                scheduler.getPendingJobReasonsHistory(JOB_ID)
                    .filter { it.timestampMillis >= since }
                    .joinToString(" ", "[", "]") { "${time(it.timestampMillis)} ${reasons(it.pendingJobReasons)}" }
            Build.VERSION.SDK_INT >= 34 -> pendingReason(scheduler.getPendingJobReason(JOB_ID))
            else -> "yes"
        }
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

    private fun exits(activity: ActivityManager, since: Long): String {
        if (Build.VERSION.SDK_INT < 30) return "n/a"
        return activity.getHistoricalProcessExitReasons(context.packageName, 0, 5)
            .filter { it.timestamp >= since }
            .joinToString(" ", "[", "]") {
                "${time(it.timestamp)} ${constantName(ApplicationExitInfo::class.java, "REASON_", it.reason)} (${it.description})"
            }
    }

    private fun pendingReason(reason: Int) = constantName(JobScheduler::class.java, "PENDING_JOB_REASON_", reason)

    private fun time(millis: Long) = Instant.ofEpochMilli(millis).truncatedTo(ChronoUnit.SECONDS).toString()

    private fun constantName(type: Class<*>, prefix: String, value: Int): String = type.fields
        .firstOrNull { it.name.startsWith(prefix) && Modifier.isStatic(it.modifiers) && it.type == Int::class.javaPrimitiveType && it.getInt(null) == value }
        ?.name?.removePrefix(prefix)?.lowercase() ?: "$value"
}
