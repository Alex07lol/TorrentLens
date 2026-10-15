package dev.torrentlens.core.torrent.engine

/** Engine-level session counters surfaced on the dashboard. */
data class SessionSnapshot(
    val isRunning: Boolean = false,
    val downloadRateBytesPerSec: Long = 0,
    val uploadRateBytesPerSec: Long = 0,
    val dhtNodes: Int = 0,
    val isFirewalled: Boolean = false,
    val activeTasks: Int = 0,
)
