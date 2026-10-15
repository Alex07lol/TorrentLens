package dev.torrentlens.torrentlens.service

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import dev.torrentlens.torrentlens.torrent.EngineHolder

/**
 * User-initiated transfer foreground service.
 *
 * Android requires an ongoing, visible notification while a transfer runs in the
 * background. The service is *not* a promise that a transfer continues under any
 * power-management configuration — the app surfaces that honestly, and the
 * engine reconciles state from the database on the next launch.
 */
class TorrentDownloadService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "Transferring"
                val notification = Notifications.build(
                    this,
                    "TorrentLens",
                    title,
                    progressPercent = null,
                    indeterminate = true,
                )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        Notifications.NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                    )
                } else {
                    startForeground(Notifications.NOTIFICATION_ID, notification)
                }
            }
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        // The engine keeps its own session; the service only owns visibility.
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "dev.torrentlens.action.START_TRANSFER"
        const val ACTION_STOP = "dev.torrentlens.action.STOP_TRANSFER"
        const val EXTRA_TITLE = "title"

        fun start(context: Context, title: String) {
            val intent = Intent(context, TorrentDownloadService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, TorrentDownloadService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}
