//
//  FABackgroundRefreshJobService.kt
//  FurAffinity (Android)
//
//  Android's BGAppRefreshTask: a JobScheduler job running the shared
//  `BackgroundRefreshManager.performFetchAndNotify()`. Like iOS's, each run schedules the
//  next at the budget's next slot. FANotificationBridge schedules it.
//
//  JobScheduler rather than WorkManager: WorkManager runs due work directly in a live
//  process, outside any job, where Android blocks a backgrounded app's network. A job
//  JobScheduler dispatches has network for as long as it runs.
//

package fur.affinity.ui

import android.app.job.JobParameters
import android.app.job.JobService
import android.app.usage.UsageStatsManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class FABackgroundRefreshJobService : JobService() {
    companion object {
        private const val TAG = "FABackgroundRefresh"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    // By job id: the scheduled job and a debug one can run in one instance. Main thread only.
    private val runs = mutableMapOf<Int, Job>()

    override fun onStartJob(params: JobParameters): Boolean {
        val run = scope.launch {
            try {
                FurAffinityUIAppDelegate.shared.performBackgroundRefresh(
                    deviceConditions(params),
                    params.isScheduled,
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "Background refresh threw: $e")
            } finally {
                jobFinished(params, false)
            }
        }
        // Once the run is over, so the onStopJob that scheduling the same id can cause
        // cancels nothing; and not after a stop, which the system retries instead.
        if (params.isScheduled) run.invokeOnCompletion { cause ->
            if (cause == null) FurAffinityUIAppDelegate.shared.scheduleBackgroundRefresh()
        }
        runs[params.jobId] = run
        return true
    }

    /// The system took the job back (constraint lost, time limit): retry it later.
    override fun onStopJob(params: JobParameters): Boolean {
        val run = runs.remove(params.jobId)
        if (run?.isActive == true) {
            run.cancel()
            // The coroutine's cancellation doesn't reach the Swift task it awaits.
            val reason = if (Build.VERSION.SDK_INT >= 31) stopReason(params.stopReason) else "unknown"
            FurAffinityUIAppDelegate.shared.cancelBackgroundRefresh(reason)
        }
        return true
    }

    private val JobParameters.isScheduled get() = jobId == FANotificationBridge.SCHEDULED_JOB_ID

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    // What Android throttles the job by, so a tester's log shows why runs are sparse.
    private fun deviceConditions(params: JobParameters): String {
        val bucket = FANotificationBridge.bucket(getSystemService(UsageStatsManager::class.java)?.appStandbyBucket)
        val charging = getSystemService(BatteryManager::class.java)?.isCharging
        val idle = getSystemService(PowerManager::class.java)?.isDeviceIdleMode
        val job = if (params.isScheduled) "scheduled" else "debug"
        val history = if (params.isScheduled) ", ${FANotificationBridge.schedulingDiagnostics()}" else ""
        return "standby bucket: $bucket, charging: $charging, device idle: $idle, ${network()}, job: $job$history"
    }

    private fun network(): String = try {
        val connectivity = getSystemService(ConnectivityManager::class.java)
        val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
        val type = when {
            capabilities == null -> "none"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            else -> "other"
        }
        "network: $type, validated: ${capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true}"
    } catch (e: Exception) {
        "network: <$e>"
    }

    private fun stopReason(reason: Int): String = when (reason) {
        JobParameters.STOP_REASON_CANCELLED_BY_APP -> "cancelled by app"
        JobParameters.STOP_REASON_PREEMPT -> "preempt"
        JobParameters.STOP_REASON_TIMEOUT -> "timeout"
        JobParameters.STOP_REASON_DEVICE_STATE -> "device state"
        JobParameters.STOP_REASON_CONSTRAINT_CONNECTIVITY -> "connectivity"
        JobParameters.STOP_REASON_BACKGROUND_RESTRICTION -> "background restriction"
        JobParameters.STOP_REASON_QUOTA -> "quota"
        JobParameters.STOP_REASON_APP_STANDBY -> "app standby"
        JobParameters.STOP_REASON_USER -> "user"
        JobParameters.STOP_REASON_SYSTEM_PROCESSING -> "system processing"
        JobParameters.STOP_REASON_TIMEOUT_ABANDONED -> "timeout abandoned"
        else -> "$reason"
    }
}
