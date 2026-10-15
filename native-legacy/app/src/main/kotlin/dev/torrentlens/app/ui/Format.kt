package dev.torrentlens.app.ui

import java.util.Locale
import kotlin.math.abs

/** Shared formatting so every screen reports speed and size the same way. */
object Format {

    fun rate(bytesPerSec: Long): String = when {
        bytesPerSec <= 0 -> "0 B/s"
        bytesPerSec < 1024 -> "$bytesPerSec B/s"
        bytesPerSec < 1024 * 1024 -> "${bytesPerSec / 1024} KiB/s"
        else -> String.format(Locale.US, "%.1f MiB/s", bytesPerSec / 1024.0 / 1024.0)
    }

    fun size(bytes: Long): String {
        if (bytes <= 0) return "0 B"
        val units = listOf("B", "KiB", "MiB", "GiB", "TiB")
        var value = bytes.toDouble()
        var unit = 0
        while (value >= 1024 && unit < units.lastIndex) {
            value /= 1024
            unit++
        }
        return if (unit == 0) "$bytes B" else String.format(Locale.US, "%.1f %s", value, units[unit])
    }

    fun eta(seconds: Long?): String {
        if (seconds == null) return "—"
        if (seconds <= 0) return "finishing"
        val minutes = seconds / 60
        val hours = minutes / 60
        return when {
            hours > 0 -> "${hours}h ${minutes % 60}m"
            minutes > 0 -> "${minutes}m"
            else -> "${seconds}s"
        }
    }

    fun percent(value: Int): String = "$value%"

    /** Keeps very long torrent names from breaking the layout. */
    fun truncateMiddle(value: String, max: Int = 46): String =
        if (value.length <= max) value else value.take(max / 2 - 1) + "…" + value.takeLast(max / 2 - 1)

    fun relativeAge(epochMillis: Long, now: Long = System.currentTimeMillis()): String {
        val delta = abs(now - epochMillis) / 1000
        return when {
            delta < 60 -> "just now"
            delta < 3600 -> "${delta / 60}m ago"
            delta < 86_400 -> "${delta / 3600}h ago"
            else -> "${delta / 86_400}d ago"
        }
    }
}
