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

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class FABackgroundRefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result =
        if (FurAffinityUIAppDelegate.shared.performBackgroundRefresh()) Result.success() else Result.failure()
}
