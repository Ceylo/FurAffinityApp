//
//  FABackgroundRefreshWorker.kt
//  FurAffinity (Android)
//
//  Android's BGAppRefreshTask: a periodic WorkManager job running the shared
//  `BackgroundRefreshManager.performFetchAndNotify()`. Periodic rather than iOS's
//  self-rechaining one-shot, since replacing the work from inside the running worker
//  would cancel it. FANotificationBridge schedules it.
//

package fur.affinity.ui

import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.BatteryManager
import android.os.PowerManager
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class FABackgroundRefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result =
        if (FurAffinityUIAppDelegate.shared.performBackgroundRefresh(deviceConditions())) Result.success() else Result.failure()

    // What Android throttles the job by, so a tester's log shows why runs are sparse.
    private fun deviceConditions(): String {
        val bucket = when (val raw = applicationContext.getSystemService(UsageStatsManager::class.java)?.appStandbyBucket) {
            UsageStatsManager.STANDBY_BUCKET_ACTIVE -> "active"
            UsageStatsManager.STANDBY_BUCKET_WORKING_SET -> "working set"
            UsageStatsManager.STANDBY_BUCKET_FREQUENT -> "frequent"
            UsageStatsManager.STANDBY_BUCKET_RARE -> "rare"
            UsageStatsManager.STANDBY_BUCKET_RESTRICTED -> "restricted"
            else -> "$raw"
        }
        val charging = applicationContext.getSystemService(BatteryManager::class.java)?.isCharging
        val idle = applicationContext.getSystemService(PowerManager::class.java)?.isDeviceIdleMode
        return "standby bucket: $bucket, charging: $charging, device idle: $idle, attempt: ${runAttemptCount + 1}"
    }
}
