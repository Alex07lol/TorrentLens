package dev.torrentlens.core.torrent.engine

import dev.torrentlens.core.domain.torrent.TorrentFileList
import dev.torrentlens.core.domain.model.TorrentTaskStats
import java.io.File
import kotlinx.coroutines.flow.Flow

/** Session-wide configuration applied when the engine starts. */
data class EngineOptions(
    val sessionDownloadLimitBytesPerSec: Long = 0,
    val sessionUploadLimitBytesPerSec: Long = 0,
    val enableDht: Boolean = true,
    val enableLsd: Boolean = true,
    val maxActiveDownloads: Int = 3,
    val listenPort: Int = 0,
)

/**
 * The engine contract the rest of TorrentLens depends on.
 *
 * Everything libtorrent-specific stays behind this interface so the UI, the
 * database and the notification layer never see engine types. That is also what
 * makes swapping libtorrent4j for another maintained binding a contained change.
 */
interface TorrentEngine {

    suspend fun start(options: EngineOptions)

    suspend fun stop()

    val isRunning: Boolean

    /** Adds a magnet and resolves its metadata. Returns the v1 info-hash hex. */
    suspend fun addMagnet(magnetUri: String, saveDir: File): Result<String>

    /** Adds an already-read `.torrent` descriptor. Returns the v1 info-hash hex. */
    suspend fun addTorrentFile(descriptor: ByteArray, saveDir: File): Result<String>

    /** Metadata for a task, or null while it is still being fetched. */
    suspend fun metadata(infoHashHex: String): TorrentFileList?

    /** Applies file selection using the indices of [metadata]'s accepted order. */
    suspend fun setFileSelection(infoHashHex: String, selectedRelativePaths: Set<String>): Result<Unit>

    suspend fun pause(infoHashHex: String): Result<Unit>

    suspend fun resume(infoHashHex: String): Result<Unit>

    suspend fun remove(infoHashHex: String, deleteFiles: Boolean): Result<Unit>

    suspend fun setTaskLimits(
        infoHashHex: String,
        uploadLimitBytesPerSec: Long,
        downloadLimitBytesPerSec: Long,
    ): Result<Unit>

    suspend fun setSessionLimits(downloadBytesPerSec: Long, uploadBytesPerSec: Long)

    /** Adds a tracker to a running task. */
    suspend fun addTracker(infoHashHex: String, announceUrl: String): Result<Unit>

    /**
     * Status for every task the engine knows about, keyed by info-hash hex.
     * Polled rather than pushed: libtorrent's alert stream is far more surface
     * area than this app needs, and status polling is cheap.
     */
    fun observeStatus(): Flow<Map<String, TorrentTaskStats>>

    /** One-shot status read, used when a task is first added. */
    suspend fun status(infoHashHex: String): TorrentTaskStats?

    /** Remaining tracker URLs for a task, for the peer/upload transparency view. */
    suspend fun trackers(infoHashHex: String): List<String>
}

/** Engine failures translated into user-actionable messages. */
enum class EngineError(val message: String) {
    NOT_STARTED("The torrent engine is not running."),
    METADATA_TIMEOUT("Could not fetch torrent metadata from peers or the DHT in time."),
    UNKNOWN_TORRENT("That torrent is no longer in the engine."),
    INVALID_DESCRIPTOR("That .torrent file could not be read."),
    DUPLICATE("That torrent is already in the list."),
    INTERNAL("The torrent engine reported an error."),
}
