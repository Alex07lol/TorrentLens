package dev.torrentlens.core.torrent.engine

import dev.torrentlens.core.domain.model.TorrentTaskStats
import dev.torrentlens.core.domain.model.TorrentTaskState
import dev.torrentlens.core.domain.torrent.RawTorrentFile
import dev.torrentlens.core.domain.torrent.TorrentFileList
import dev.torrentlens.core.domain.torrent.TorrentFileListSanitizer
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import org.libtorrent4j.Priority
import org.libtorrent4j.SessionManager
import org.libtorrent4j.Sha1Hash
import org.libtorrent4j.TorrentHandle
import org.libtorrent4j.TorrentInfo
import org.libtorrent4j.TorrentStatus

/**
 * libtorrent4j-backed [TorrentEngine].
 *
 * Deliberate choices:
 * - Magnet metadata is resolved with [SessionManager.fetchMagnet], which uses the
 *   DHT/trackers to fetch the info-dict; the resulting `.torrent` bytes are then
 *   added normally. This keeps one code path for magnets and files.
 * - Every native call runs on [Dispatchers.IO]; the swig layer is not thread-safe
 *   against the UI thread and `fetchMagnet` blocks.
 * - File lists are passed through [TorrentFileListSanitizer] before they reach
 *   the UI, because the names come from remote peers.
 */
class LibtorrentEngine(
    private val magnetTimeoutSeconds: Int = 90,
    private val statusPollMillis: Long = 1_000,
) : TorrentEngine {

    private var session: SessionManager? = null
    private var options: EngineOptions = EngineOptions()

    /**
     * Live handles keyed by lowercase info-hash hex. Concurrent because the
     * status flow reads this map while adds/removes mutate it.
     */
    private val handles = java.util.concurrent.ConcurrentHashMap<String, TorrentHandle>()

    override val isRunning: Boolean get() = session?.isRunning() == true

    override suspend fun start(options: EngineOptions) = withContext(Dispatchers.IO) {
        if (isRunning) return@withContext
        this@LibtorrentEngine.options = options
        val manager = SessionManager()
        manager.downloadRateLimit(options.sessionDownloadLimitBytesPerSec.toInt())
        manager.uploadRateLimit(options.sessionUploadLimitBytesPerSec.toInt())
        manager.maxActiveDownloads(options.maxActiveDownloads)
        manager.start()
        if (options.enableDht) manager.startDht()
        session = manager
    }

    override suspend fun stop() = withContext(Dispatchers.IO) {
        val manager = session ?: return@withContext
        // Ask libtorrent to persist resume data so a restart re-checks existing
        // data instead of re-downloading completed pieces.
        handles.values.forEach { handle ->
            runCatching { if (handle.isValid() && handle.needSaveResumeData()) handle.saveResumeData() }
        }
        runCatching { manager.stop() }
        handles.clear()
        session = null
    }

    override suspend fun addMagnet(magnetUri: String, saveDir: File): Result<String> =
        withContext(Dispatchers.IO) {
            val manager = session ?: return@withContext Result.failure(EngineFailure(EngineError.NOT_STARTED))
            saveDir.mkdirs()
            // Blocks until the info-dict is fetched from peers/DHT (or times out).
            val descriptor = try {
                manager.fetchMagnet(magnetUri, magnetTimeoutSeconds, saveDir)
            } catch (t: Throwable) {
                // Only metadata acquisition failures are reported as a timeout; a
                // duplicate or invalid descriptor must keep its own reason.
                return@withContext Result.failure(EngineFailure(EngineError.METADATA_TIMEOUT, t))
            }
            try {
                Result.success(addDescriptor(manager, TorrentInfo(descriptor), saveDir))
            } catch (failure: EngineFailure) {
                Result.failure(failure)
            } catch (t: Throwable) {
                Result.failure(EngineFailure(EngineError.INTERNAL, t))
            }
        }

    override suspend fun addTorrentFile(descriptor: ByteArray, saveDir: File): Result<String> =
        withContext(Dispatchers.IO) {
            val manager = session ?: return@withContext Result.failure(EngineFailure(EngineError.NOT_STARTED))
            saveDir.mkdirs()
            val info = try {
                TorrentInfo(descriptor).takeIf { it.isValid() }
                    ?: return@withContext Result.failure(EngineFailure(EngineError.INVALID_DESCRIPTOR))
            } catch (t: Throwable) {
                return@withContext Result.failure(EngineFailure(EngineError.INVALID_DESCRIPTOR, t))
            }
            try {
                Result.success(addDescriptor(manager, info, saveDir))
            } catch (failure: EngineFailure) {
                Result.failure(failure)
            } catch (t: Throwable) {
                Result.failure(EngineFailure(EngineError.INTERNAL, t))
            }
        }

    private fun addDescriptor(manager: SessionManager, info: TorrentInfo, saveDir: File): String {
        val hash = info.infoHash()
        val hex = hash.toHex().lowercase()
        if (handles.containsKey(hex)) throw EngineFailure(EngineError.DUPLICATE)
        manager.download(info, saveDir)
        val handle = manager.find(hash)
            ?: throw EngineFailure(EngineError.INTERNAL)
        handles[hex] = handle
        return hex
    }

    override suspend fun metadata(infoHashHex: String): TorrentFileList? = withContext(Dispatchers.IO) {
        val handle = handle(infoHashHex) ?: return@withContext null
        val info = handle.torrentFile() ?: return@withContext null
        val files = info.files()
        val raw = (0 until files.numFiles()).map { index ->
            RawTorrentFile(
                path = files.filePath(index),
                lengthBytes = files.fileSize(index),
                isPaddingFile = files.padFileAt(index),
            )
        }
        TorrentFileListSanitizer.sanitize(raw)
    }

    override suspend fun setFileSelection(
        infoHashHex: String,
        selectedRelativePaths: Set<String>,
    ): Result<Unit> = withContext(Dispatchers.IO) {
        val handle = handle(infoHashHex) ?: return@withContext Result.failure(EngineFailure(EngineError.UNKNOWN_TORRENT))
        val info = handle.torrentFile() ?: return@withContext Result.failure(EngineFailure(EngineError.UNKNOWN_TORRENT))
        val files = info.files()
        runCatching {
            val priorities = Array(files.numFiles()) { index ->
                val normalized = files.filePath(index).replace('\\', '/').removePrefix("/")
                if (selectedRelativePaths.contains(normalized)) Priority.DEFAULT else Priority.IGNORE
            }
            handle.prioritizeFiles(priorities)
        }.mapCatching { }
            .recoverCatching { throw EngineFailure(EngineError.INTERNAL, it) }
    }

    override suspend fun pause(infoHashHex: String): Result<Unit> = withContext(Dispatchers.IO) {
        control(infoHashHex) { it.pause() }
    }

    override suspend fun resume(infoHashHex: String): Result<Unit> = withContext(Dispatchers.IO) {
        control(infoHashHex) { it.resume() }
    }

    override suspend fun remove(infoHashHex: String, deleteFiles: Boolean): Result<Unit> =
        withContext(Dispatchers.IO) {
            val manager = session ?: return@withContext Result.failure(EngineFailure(EngineError.NOT_STARTED))
            val key = infoHashHex.lowercase()
            val handle = handles.remove(key)
                ?: return@withContext Result.failure(EngineFailure(EngineError.UNKNOWN_TORRENT))
            runCatching {
                // Payload deletion is handled by the app layer, which owns the
                // Storage Access Framework handles. The engine only releases the
                // task, so the user's files are never removed implicitly.
                if (deleteFiles) { /* handled by the caller with SAF */ }
                manager.remove(handle)
            }.mapCatching { }
                .recoverCatching { throw EngineFailure(EngineError.INTERNAL, it) }
        }

    override suspend fun setTaskLimits(
        infoHashHex: String,
        uploadLimitBytesPerSec: Long,
        downloadLimitBytesPerSec: Long,
    ): Result<Unit> = withContext(Dispatchers.IO) {
        control(infoHashHex) { handle ->
            handle.setUploadLimit(uploadLimitBytesPerSec.coerceIn(0, Int.MAX_VALUE.toLong()).toInt())
            handle.setDownloadLimit(downloadLimitBytesPerSec.coerceIn(0, Int.MAX_VALUE.toLong()).toInt())
        }
    }

    override suspend fun setSessionLimits(downloadBytesPerSec: Long, uploadBytesPerSec: Long): Unit =
        withContext(Dispatchers.IO) {
            session?.let {
                it.downloadRateLimit(downloadBytesPerSec.coerceIn(0, Int.MAX_VALUE.toLong()).toInt())
                it.uploadRateLimit(uploadBytesPerSec.coerceIn(0, Int.MAX_VALUE.toLong()).toInt())
            }
            Unit
        }

    override suspend fun addTracker(infoHashHex: String, announceUrl: String): Result<Unit> =
        withContext(Dispatchers.IO) {
            control(infoHashHex) { handle ->
                handle.addTracker(org.libtorrent4j.AnnounceEntry(announceUrl))
            }
        }

    override suspend fun trackers(infoHashHex: String): List<String> = withContext(Dispatchers.IO) {
        handle(infoHashHex)?.trackers()?.map { it.url() } ?: emptyList()
    }

    override suspend fun status(infoHashHex: String): TorrentTaskStats? = withContext(Dispatchers.IO) {
        val handle = handle(infoHashHex) ?: return@withContext null
        runCatching { handle.status().toStats() }.getOrNull()
    }

    override fun observeStatus(): Flow<Map<String, TorrentTaskStats>> = flow {
        while (true) {
            val snapshot = withContext(Dispatchers.IO) {
                handles.mapNotNull { (hex, handle) ->
                    runCatching { hex to handle.status().toStats() }.getOrNull()
                }.toMap()
            }
            if (snapshot.isNotEmpty()) emit(snapshot)
            delay(statusPollMillis)
        }
    }.flowOn(Dispatchers.Default)

    private fun handle(infoHashHex: String): TorrentHandle? =
        handles[infoHashHex.lowercase()]?.takeIf { it.isValid() }

    private fun control(infoHashHex: String, block: (TorrentHandle) -> Unit): Result<Unit> {
        val handle = handle(infoHashHex) ?: return Result.failure(EngineFailure(EngineError.UNKNOWN_TORRENT))
        return runCatching { block(handle) }.mapCatching { }
            .recoverCatching { throw EngineFailure(EngineError.INTERNAL, it) }
    }

    private fun TorrentStatus.toStats(): TorrentTaskStats = TorrentTaskStats(
        progress = progress().toDouble(),
        downloadedBytes = totalDone(),
        totalBytes = total(),
        downloadRateBytesPerSec = downloadRate().toLong(),
        uploadRateBytesPerSec = uploadRate().toLong(),
        numPeers = numPeers(),
        numSeeds = numSeeds(),
        state = when (state()) {
            TorrentStatus.State.DOWNLOADING_METADATA -> TorrentTaskState.METADATA
            TorrentStatus.State.DOWNLOADING -> TorrentTaskState.DOWNLOADING
            TorrentStatus.State.SEEDING -> TorrentTaskState.SEEDING
            TorrentStatus.State.FINISHED -> TorrentTaskState.COMPLETE
            TorrentStatus.State.CHECKING_FILES,
            TorrentStatus.State.CHECKING_RESUME_DATA,
            -> TorrentTaskState.QUEUED
            TorrentStatus.State.UNKNOWN -> TorrentTaskState.QUEUED
        },
        errorMessage = errorCode().takeIf { it.isError }?.message,
    )
}

/** Wraps an [EngineError] so callers can branch on it without string matching. */
class EngineFailure(val error: EngineError, cause: Throwable? = null) : Exception(error.message, cause)
