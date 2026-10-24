//
//  FABackgroundRefreshJobService.kt
//  FurAffinity (Android)
//
//  Android's BGAppRefreshTask: a periodic JobScheduler job running the shared
//  `BackgroundRefreshManager.performFetchAndNotify()`. Periodic rather than iOS's
//  self-rechaining one-shot, since rescheduling restarts the period. FANotificationBridge
//  schedules it.
//
//  JobScheduler rather than WorkManager: WorkManager runs due work directly in a live
//  process, outside any job, where Android blocks a backgrounded app's network. A job
//  JobScheduler dispatches has network for as long as it runs.
//

package fur.affinity.ui

import android.app.job.JobParameters
import android.app.job.JobService
import android.app.usage.UsageStatsManager
import android.os.BatteryManager
import android.os.PowerManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class FABackgroundRefreshJobService : JobService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    // By job id: the periodic job and a debug one-off can run in one instance. Main thread only.
    private val runs = mutableMapOf<Int, Job>()

    override fun onStartJob(params: JobParameters): Boolean {
        runs[params.jobId] = scope.launch {
            FurAffinityUIAppDelegate.shared.performBackgroundRefresh(deviceConditions(params))
            jobFinished(params, false)
        }
        return true
    }

    /// The system took the job back (constraint lost, time limit): retry it later.
    override fun onStopJob(params: JobParameters): Boolean {
        runs.remove(params.jobId)?.cancel()
        return true
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    // What Android throttles the job by, so a tester's log shows why runs are sparse.
    private fun deviceConditions(params: JobParameters): String {
        val bucket = when (val raw = getSystemService(UsageStatsManager::class.java)?.appStandbyBucket) {
            UsageStatsManager.STANDBY_BUCKET_ACTIVE -> "active"
            UsageStatsManager.STANDBY_BUCKET_WORKING_SET -> "working set"
            UsageStatsManager.STANDBY_BUCKET_FREQUENT -> "frequent"
            UsageStatsManager.STANDBY_BUCKET_RARE -> "rare"
            UsageStatsManager.STANDBY_BUCKET_RESTRICTED -> "restricted"
            else -> "$raw"
        }
        val charging = getSystemService(BatteryManager::class.java)?.isCharging
        val idle = getSystemService(PowerManager::class.java)?.isDeviceIdleMode
        val job = if (params.jobId == FANotificationBridge.PERIODIC_JOB_ID) "periodic" else "one-off"
        return "standby bucket: $bucket, charging: $charging, device idle: $idle, job: $job"
    }
}
