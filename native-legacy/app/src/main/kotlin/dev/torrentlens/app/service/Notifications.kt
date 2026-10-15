package dev.torrentlens.app.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import dev.torrentlens.app.R

/**
 * Notification channels and the progress notification used by the download
 * foreground service.
 *
 * The notification is intentionally honest: it shows what is actually happening
 * (including "paused") and never implies the transfer is guaranteed to continue.
 */
object Notifications {

    const val DOWNLOADS_CHANNEL_ID = "downloads"
    const val RELEASES_CHANNEL_ID = "releases"
    const val DOWNLOAD_NOTIFICATION_ID = 1001

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(
                DOWNLOADS_CHANNEL_ID,
                context.getString(R.string.download_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = context.getString(R.string.download_channel_description)
                setShowBadge(false)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                RELEASES_CHANNEL_ID,
                context.getString(R.string.releases_channel_name),
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply { description = context.getString(R.string.releases_channel_description) },
        )
    }

    fun downloadProgressNotification(
        context: Context,
        title: String,
        activeCount: Int,
        totalBytesPerSec: Long,
        detail: String,
        paused: Boolean,
        indeterminate: Boolean,
        progressPercent: Int,
    ): android.app.Notification {
        val subtitle = if (activeCount > 1) "$activeCount active • $detail" else detail
        return NotificationCompat.Builder(context, DOWNLOADS_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setOngoing(!paused)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setProgress(100, progressPercent.coerceIn(0, 100), indeterminate)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    fun notifyNewRelease(context: Context, id: Int, title: String, text: String) {
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return
        runCatching {
            manager.notify(
                id,
                NotificationCompat.Builder(context, RELEASES_CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.stat_notify_sync)
                    .setContentTitle(title)
                    .setContentText(text)
                    .setAutoCancel(true)
                    .build(),
            )
        }
    }
}
