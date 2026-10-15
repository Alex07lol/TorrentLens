package dev.torrentlens.core.domain.model

/** Lifecycle of a download as TorrentLens models it (engine-agnostic). */
enum class TorrentTaskState {
    /** Added, waiting for metadata (magnet) or for the engine to start. */
    METADATA,
    QUEUED,
    DOWNLOADING,
    SEEDING,
    PAUSED,
    COMPLETE,
    ERROR,
    ;

    val isActive: Boolean get() = this == METADATA || this == QUEUED || this == DOWNLOADING || this == SEEDING
    val isTerminal: Boolean get() = this == COMPLETE || this == ERROR
}

/** A point-in-time status snapshot from the engine. */
data class TorrentTaskStats(
    val progress: Double = 0.0,
    val downloadedBytes: Long = 0,
    val totalBytes: Long = 0,
    val downloadRateBytesPerSec: Long = 0,
    val uploadRateBytesPerSec: Long = 0,
    val numPeers: Int = 0,
    val numSeeds: Int = 0,
    val state: TorrentTaskState = TorrentTaskState.QUEUED,
    val errorMessage: String? = null,
) {
    /** 0..100, clamped, safe when total is unknown. */
    val percent: Int get() = if (totalBytes <= 0) 0 else ((progress * 100).toInt()).coerceIn(0, 100)

    /** Rough time remaining in seconds, or null when it cannot be estimated. */
    val etaSeconds: Long?
        get() {
            if (state != TorrentTaskState.DOWNLOADING || downloadRateBytesPerSec <= 0L) return null
            val remaining = totalBytes - downloadedBytes
            return if (remaining <= 0) 0 else remaining / downloadRateBytesPerSec
        }
}

/** Per-task bandwidth/seeding policy. */
data class TorrentTaskOptions(
    val uploadLimitBytesPerSec: Long = 0,   // 0 = unlimited
    val downloadLimitBytesPerSec: Long = 0, // 0 = unlimited
    val seedingEnabled: Boolean = true,
    val seedRatioLimit: Double? = null,
    val seedForMinutes: Int? = null,
)

data class SelectedFile(
    val relativePath: String,
    val sizeBytes: Long,
    val selected: Boolean,
)
