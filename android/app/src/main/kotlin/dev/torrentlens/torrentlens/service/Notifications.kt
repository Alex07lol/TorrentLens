package dev.torrentlens.torrentlens.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import dev.torrentlens.torrentlens.R

/** Creates the single notification channel used for transfer progress. */
object Notifications {
    const val CHANNEL_ID = "torrentlens.transfers"
    const val NOTIFICATION_ID = 4201

    fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Transfers",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Ongoing BitTorrent transfers started by you."
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    /**
     * Builds the ongoing notification. Progress is only shown when a real total
     * is known, so the app never displays fabricated percentages.
     */
    fun build(
        context: Context,
        title: String,
        text: String,
        progressPercent: Int?,
        indeterminate: Boolean = false,
    ): Notification {
        ensureChannel(context)
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)

        if (indeterminate) {
            builder.setProgress(0, 0, true)
        } else if (progressPercent != null) {
            builder.setProgress(100, progressPercent.coerceIn(0, 100), false)
        }
        return builder.build()
    }
}
