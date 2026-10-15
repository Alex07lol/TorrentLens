package dev.torrentlens.app.work

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-arms *scheduled release checks* after a reboot.
 *
 * Transfers are deliberately not resumed here: silently restarting a download
 * after a reboot would spend the user's data without them asking. Tasks keep
 * their persisted state and resume when the user opens the app.
 */
class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            ManifestCheckScheduler.schedule(context, checkIntervalMinutes = 1440)
        }
    }
}
