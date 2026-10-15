package dev.torrentlens.app.service

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import dev.torrentlens.app.TorrentLensApplication
import dev.torrentlens.app.di.AppContainer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Foreground service that keeps user-initiated transfers running while the app
 * is not in the foreground (ADR 0004).
 *
 * It does not promise unlimited background downloading: Android may stop the
 * service when the user force-stops the app, when data-sync time limits are
 * reached, or under aggressive OEM battery managers. The persistent notification
 * is the honest signal of what is actually happening.
 */
class TorrentDownloadService : Service() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private lateinit var container: AppContainer

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        container = (application as TorrentLensApplication).container
        promoteToForeground(
            title = "TorrentLens",
            detail = "Preparing the torrent engine…",
            activeCount = 0,
            rate = 0,
            paused = false,
        )
        observeTransfers()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_PAUSE_ALL) {
            scope.launch {
                container.taskRepository.findUnfinished().forEach { container.engine.pause(it.id) }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        stopForegroundCompat()
        super.onDestroy()
    }

    private fun observeTransfers() {
        scope.launch {
            runCatching {
                container.engine.observeStatus().collect { snapshot ->
                    val active = snapshot.values.filter { it.state.isActive }
                    if (active.isEmpty()) {
                        // Paused or finished: there is no transfer to keep alive, so
                        // release the foreground slot instead of holding it with a
                        // notification that would overstate what is happening.
                        stopForegroundCompat()
                        stopSelf()
                        return@collect
                    }
                    val rate = active.sumOf { it.downloadRateBytesPerSec }
                    val total = active.sumOf { it.totalBytes }
                    val done = active.sumOf { it.downloadedBytes }
                    val percent = if (total <= 0) 0 else ((done * 100) / total).toInt()
                    val peers = active.sumOf { it.numPeers }
                    promoteToForeground(
                        title = if (active.size == 1) "Downloading 1 torrent" else "Downloading ${active.size} torrents",
                        detail = "${formatRate(rate)} • $peers peers",
                        activeCount = active.size,
                        rate = rate,
                        paused = false,
                        percent = percent,
                        indeterminate = total <= 0,
                    )
                }
            }
        }
    }

    private fun promoteToForeground(
        title: String,
        detail: String,
        activeCount: Int,
        rate: Long,
        paused: Boolean,
        percent: Int = 0,
        indeterminate: Boolean = true,
    ) {
        val notification = Notifications.downloadProgressNotification(
            context = this,
            title = title,
            activeCount = activeCount,
            totalBytesPerSec = rate,
            detail = detail,
            paused = paused,
            indeterminate = indeterminate,
            progressPercent = percent,
        )
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        } else {
            0
        }
        ServiceCompat.startForeground(this, Notifications.DOWNLOAD_NOTIFICATION_ID, notification, type)
    }

    private fun stopForegroundCompat() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
    }

    private fun formatRate(bytesPerSec: Long): String = when {
        bytesPerSec <= 0 -> "0 B/s"
        bytesPerSec < 1024 -> "$bytesPerSec B/s"
        bytesPerSec < 1024 * 1024 -> "${bytesPerSec / 1024} KiB/s"
        else -> String.format("%.1f MiB/s", bytesPerSec / 1024.0 / 1024.0)
    }

    companion object {
        const val ACTION_PAUSE_ALL = "dev.torrentlens.app.action.PAUSE_ALL"

        fun start(context: Context) {
            ContextCompat.startForegroundService(context, Intent(context, TorrentDownloadService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, TorrentDownloadService::class.java))
        }
    }
}
