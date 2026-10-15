package dev.torrentlens.app.work

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dev.torrentlens.app.TorrentLensApplication
import dev.torrentlens.app.data.SubscriptionManager
import java.util.concurrent.TimeUnit

/**
 * Scheduled GitHub release checks.
 *
 * This is deferrable work, so it belongs on WorkManager rather than a foreground
 * service: it runs inside a maintenance window, requires connectivity, and must
 * tolerate being delayed. It never downloads anything by itself.
 */
class ManifestCheckWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val container = (applicationContext as? TorrentLensApplication)?.container
            ?: return Result.success()
        return runCatching { SubscriptionManager(container).checkAll() }
            .fold(onSuccess = { Result.success() }, onFailure = { Result.retry() })
    }
}

object ManifestCheckScheduler {

    const val UNIQUE_WORK_NAME = "torrentlens-manifest-check"

    /** Android's floor for periodic work is 15 minutes. */
    private const val MIN_INTERVAL_MINUTES = 15L

    fun schedule(context: Context, checkIntervalMinutes: Int) {
        val interval = checkIntervalMinutes.toLong().coerceAtLeast(MIN_INTERVAL_MINUTES)
        val request = PeriodicWorkRequestBuilder<ManifestCheckWorker>(interval, TimeUnit.MINUTES)
            .setConstraints(
                Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build(),
            )
            .setInitialDelay(interval, TimeUnit.MINUTES)
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            UNIQUE_WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            request,
        )
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK_NAME)
    }
}
