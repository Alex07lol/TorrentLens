package dev.torrentlens.torrentlens.torrent

import java.io.File
import java.util.concurrent.ConcurrentHashMap
import org.libtorrent4j.AnnounceEntry
import org.libtorrent4j.Priority
import org.libtorrent4j.SessionManager
import org.libtorrent4j.Sha1Hash
import org.libtorrent4j.TorrentHandle
import org.libtorrent4j.TorrentInfo
import org.libtorrent4j.TorrentStatus

/**
 * The lifecycle label shared by task status and streaming snapshots, so both
 * report the same states for the same underlying libtorrent state.
 */
internal fun TorrentStatus.stateLabel(): String = when (state()) {
    TorrentStatus.State.DOWNLOADING_METADATA -> "resolvingMetadata"
    TorrentStatus.State.DOWNLOADING -> "downloading"
    TorrentStatus.State.SEEDING -> "seeding"
    TorrentStatus.State.FINISHED -> "completed"
    TorrentStatus.State.CHECKING_FILES,
    TorrentStatus.State.CHECKING_RESUME_DATA -> "checking"
    TorrentStatus.State.UNKNOWN -> "queued"
}

/** A status snapshot handed to Dart. Field names match the Dart model. */
data class TaskStatus(
    val infoHash: String,
    val state: String,
    val progress: Double,
    val downloadedBytes: Long,
    val totalBytes: Long,
    val downloadBps: Long,
    val uploadBps: Long,
    val numPeers: Int,
    val numSeeds: Int,
    val errorMessage: String?,
)

/**
 * A genuine BitTorrent engine backed by libtorrent4j.
 *
 * Design notes carried over from the native prototype (see docs/adr):
 *  - Magnet metadata is resolved with [SessionManager.fetchMagnet]; the fetched
 *    info-dict is then added through the same path as a `.torrent` file, so
 *    there is exactly one add path.
 *  - Every native call runs on a background dispatcher at the call site; the
 *    SWIG layer must not be driven from the UI thread, and `fetchMagnet` blocks.
 *  - File lists pass through [TorrentFileListSanitizer] before the app sees them.
 */
class LibtorrentEngine(
    private val magnetTimeoutSeconds: Int = 90,
) {
    @Volatile
    private var session: SessionManager? = null

    private val handles = ConcurrentHashMap<String, TorrentHandle>()

    /**
     * The active streaming window per torrent, plus the file priority to
     * restore when playback ends. Only one window per torrent is supported;
     * opening a second stream for the same torrent replaces the first.
     */
    private val streams = ConcurrentHashMap<String, StreamSession>()

    private data class StreamSession(
        val fileIndex: Int,
        val previousPriority: Priority,
        val range: IntRange,
        val deadlineMs: Int,
        val stepMs: Int,
    )

    val isRunning: Boolean get() = session?.isRunning() == true

    fun start(options: EngineOptions) {
        if (isRunning) return
        val manager = SessionManager()
        manager.downloadRateLimit(options.sessionDownloadLimitBytesPerSec.coerceToInt())
        manager.uploadRateLimit(options.sessionUploadLimitBytesPerSec.coerceToInt())
        manager.maxActiveDownloads(options.maxActiveDownloads)
        manager.start()
        if (options.enableDht) manager.startDht()
        session = manager
    }

    fun stop() {
        val manager = session ?: return
        handles.values.forEach { handle ->
            runCatching {
                if (handle.isValid() && handle.needSaveResumeData()) handle.saveResumeData()
            }
        }
        runCatching { manager.stop() }
        handles.clear()
        // Streaming windows die with the session; nothing is left to restore.
        streams.clear()
        session = null
    }

    fun addMagnet(magnetUri: String, saveDir: File): Result<String> {
        val manager = session ?: return Result.failure(EngineFailure(EngineError.NOT_STARTED))
        TorrentFileListSanitizer.ensureDirectory(saveDir)
        val descriptor = try {
            manager.fetchMagnet(magnetUri, magnetTimeoutSeconds, saveDir)
        } catch (t: Throwable) {
            return Result.failure(EngineFailure(EngineError.METADATA_TIMEOUT, t))
        }
        return try {
            Result.success(addDescriptor(manager, TorrentInfo(descriptor), saveDir))
        } catch (failure: EngineFailure) {
            Result.failure(failure)
        } catch (t: Throwable) {
            Result.failure(EngineFailure(EngineError.INTERNAL, t))
        }
    }

    fun addTorrentFile(descriptor: ByteArray, saveDir: File): Result<String> {
        val manager = session ?: return Result.failure(EngineFailure(EngineError.NOT_STARTED))
        TorrentFileListSanitizer.ensureDirectory(saveDir)
        val info = try {
            TorrentInfo(descriptor).takeIf { it.isValid() }
                ?: return Result.failure(EngineFailure(EngineError.INVALID_DESCRIPTOR))
        } catch (t: Throwable) {
            return Result.failure(EngineFailure(EngineError.INVALID_DESCRIPTOR, t))
        }
        return try {
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
        val handle = manager.find(hash) ?: throw EngineFailure(EngineError.INTERNAL)
        handles[hex] = handle
        return hex
    }

    /** Validated metadata for a task, or null while metadata is still pending. */
    fun metadata(infoHashHex: String): List<Map<String, Any?>>? {
        val handle = handle(infoHashHex) ?: return null
        val info = handle.torrentFile() ?: return null
        val files = info.files()
        val raw = (0 until files.numFiles()).map { index ->
            files.filePath(index) to files.fileSize(index)
        }
        val padding = (0 until files.numFiles()).map { index -> files.padFileAt(index) }
        val (accepted, rejected) = TorrentFileListSanitizer.sanitize(raw, padding)
        return accepted.mapIndexed { index, file ->
            mapOf(
                "index" to index,
                "path" to file.relativePath,
                "originalPath" to file.originalPath,
                "sizeBytes" to file.lengthBytes,
                "isPadding" to file.isPaddingFile,
            )
        }.also {
            if (rejected.isNotEmpty()) {
                // Callers surface this so the user knows some entries were dropped.
                lastRejected.set(rejected.map { r -> "${r.originalPath}: ${r.reason}" })
            }
        }
    }

    /** Rejections from the most recent [metadata] call, for transparency. */
    val lastRejected = java.util.concurrent.atomic.AtomicReference<List<String>>(emptyList())

    fun setFileSelection(infoHashHex: String, selectedRelativePaths: Set<String>): Result<Unit> {
        val handle = handle(infoHashHex)
            ?: return Result.failure(EngineFailure(EngineError.UNKNOWN_TORRENT))
        val info = handle.torrentFile()
            ?: return Result.failure(EngineFailure(EngineError.UNKNOWN_TORRENT))
        val files = info.files()
        return runCatching {
            val priorities = Array(files.numFiles()) { index ->
                val normalized = files.filePath(index).replace('\\', '/').removePrefix("/")
                if (selectedRelativePaths.contains(normalized)) Priority.DEFAULT else Priority.IGNORE
            }
            handle.prioritizeFiles(priorities)
            reapplyStreamAfterSelectionChange(infoHashHex, handle, files.numFiles(), selectedRelativePaths)
        }.mapCatching { }
            .recoverCatching { throw EngineFailure(EngineError.INTERNAL, it) }
    }

    /**
     * A file-selection change rewrites every file priority, which would undo an
     * active streaming window. This re-applies the window, and updates what
     * [endStreaming] will restore so the user's *new* selection wins when
     * playback ends.
     */
    private fun reapplyStreamAfterSelectionChange(
        infoHashHex: String,
        handle: TorrentHandle,
        numFiles: Int,
        selectedRelativePaths: Set<String>,
    ) {
        val key = infoHashHex.lowercase()
        val session = streams[key] ?: return
        if (session.fileIndex !in 0 until numFiles) return
        StreamQuery.applyPriority(
            handle,
            session.fileIndex,
            session.range,
            session.deadlineMs,
            session.stepMs,
        )
        val file = handle.torrentFile()?.files()?.filePath(session.fileIndex)
            ?.replace('\\', '/')?.removePrefix("/")
        if (file != null) {
            streams[key] = session.copy(
                previousPriority = if (selectedRelativePaths.contains(file)) Priority.DEFAULT else Priority.IGNORE,
            )
        }
    }

    fun pause(infoHashHex: String): Result<Unit> = control(infoHashHex) { it.pause() }
    fun resume(infoHashHex: String): Result<Unit> = control(infoHashHex) { it.resume() }

    fun remove(infoHashHex: String): Result<Unit> {
        val manager = session ?: return Result.failure(EngineFailure(EngineError.NOT_STARTED))
        val handle = handles.remove(infoHashHex.lowercase())
            ?: return Result.failure(EngineFailure(EngineError.UNKNOWN_TORRENT))
        streams.remove(infoHashHex.lowercase())
        // Payload deletion is deliberately the app's job: it owns the SAF
        // location, so the user's files are never removed implicitly.
        return runCatching { manager.remove(handle) }
            .mapCatching { }
            .recoverCatching { throw EngineFailure(EngineError.INTERNAL, it) }
    }

    fun setTaskLimits(
        infoHashHex: String,
        uploadLimitBytesPerSec: Long,
        downloadLimitBytesPerSec: Long,
    ): Result<Unit> = control(infoHashHex) { handle ->
        handle.setUploadLimit(uploadLimitBytesPerSec.coerceToInt())
        handle.setDownloadLimit(downloadLimitBytesPerSec.coerceToInt())
    }

    fun setSessionLimits(downloadBytesPerSec: Long, uploadBytesPerSec: Long) {
        session?.let {
            it.downloadRateLimit(downloadBytesPerSec.coerceToInt())
            it.uploadRateLimit(uploadBytesPerSec.coerceToInt())
        }
    }

    fun addTracker(infoHashHex: String, announceUrl: String): Result<Unit> =
        control(infoHashHex) { it.addTracker(AnnounceEntry(announceUrl)) }

    fun trackers(infoHashHex: String): List<String> =
        handle(infoHashHex)?.trackers()?.map { it.url() } ?: emptyList()

    fun status(infoHashHex: String): TaskStatus? =
        handle(infoHashHex)?.let { runCatching { it.status().toTaskStatus(infoHashHex) }.getOrNull() }

    fun allStatus(): List<TaskStatus> = handles.mapNotNull { (hex, handle) ->
        runCatching { handle.status().toTaskStatus(hex) }.getOrNull()
    }

    /** Forces a re-check of the on-disk data (used after an interrupted session). */
    fun recheck(infoHashHex: String): Result<Unit> =
        control(infoHashHex) { it.forceRecheck() }

    /**
     * Opens (or moves) a streaming window over [relativePath] and returns what
     * is readable right now.
     *
     * [firstPiece] and [lastPiece] are absolute piece indices computed by the
     * caller from the playback position and the read-ahead window. The streamed
     * file and those pieces are raised to top priority, with graded deadlines so
     * the window arrives in playback order. The file's previous priority is
     * remembered and restored by [endStreaming], so streaming never silently
     * changes the user's file selection.
     */
    fun beginStreaming(
        infoHashHex: String,
        relativePath: String,
        firstPiece: Int,
        lastPiece: Int,
        deadlineMs: Int,
        stepMs: Int,
    ): Result<StreamSnapshot> = stream(
        infoHashHex = infoHashHex,
        relativePath = relativePath,
        firstPiece = firstPiece,
        lastPiece = lastPiece,
        applyPriority = true,
        deadlineMs = deadlineMs,
        stepMs = stepMs,
    )

    /** Read-only variant of [beginStreaming]; it never touches priorities. */
    fun streamSnapshot(
        infoHashHex: String,
        relativePath: String,
        firstPiece: Int,
        lastPiece: Int,
    ): Result<StreamSnapshot> = stream(
        infoHashHex = infoHashHex,
        relativePath = relativePath,
        firstPiece = firstPiece,
        lastPiece = lastPiece,
        applyPriority = false,
        deadlineMs = 0,
        stepMs = 0,
    )

    /**
     * Releases a streaming window: drops the deadlines and restores the file's
     * previous priority. A no-op when this torrent has no window, or when the
     * window belongs to a different file.
     */
    fun endStreaming(infoHashHex: String, relativePath: String): Result<Unit> {
        val key = infoHashHex.lowercase()
        val handle = handle(infoHashHex)
        if (handle == null) {
            streams.remove(key)
            return Result.success(Unit)
        }
        val fileIndex = handle.torrentFile()?.let { StreamQuery.resolveFileIndex(it, relativePath) }
        val session = streams[key]
        if (session == null || (fileIndex != null && session.fileIndex != fileIndex)) {
            return Result.success(Unit)
        }
        streams.remove(key)
        return runCatching {
            StreamQuery.releasePriority(handle, session.fileIndex, session.previousPriority)
        }.recoverCatching { throw EngineFailure(EngineError.INTERNAL, it) }
    }

    private fun stream(
        infoHashHex: String,
        relativePath: String,
        firstPiece: Int,
        lastPiece: Int,
        applyPriority: Boolean,
        deadlineMs: Int,
        stepMs: Int,
    ): Result<StreamSnapshot> {
        val handle = handle(infoHashHex)
            ?: return Result.failure(EngineFailure(EngineError.UNKNOWN_TORRENT))
        val info = handle.torrentFile()
            ?: return Result.failure(EngineFailure(EngineError.UNKNOWN_TORRENT))
        val fileIndex = StreamQuery.resolveFileIndex(info, relativePath)
            ?: return Result.failure(EngineFailure(EngineError.FILE_NOT_FOUND))
        val range = StreamQuery.clampRange(info, firstPiece, lastPiece)
            ?: return Result.failure(EngineFailure(EngineError.INTERNAL))
        return runCatching {
            if (applyPriority) {
                val key = infoHashHex.lowercase()
                val existing = streams[key]
                val previous = if (existing == null || existing.fileIndex != fileIndex) {
                    handle.filePriority(fileIndex)
                } else {
                    existing.previousPriority
                }
                streams[key] = StreamSession(fileIndex, previous, range, deadlineMs, stepMs)
                StreamQuery.applyPriority(handle, fileIndex, range, deadlineMs, stepMs)
            }
            StreamQuery.snapshot(handle, info, infoHashHex.lowercase(), relativePath, fileIndex, range)
        }.recoverCatching { throw EngineFailure(EngineError.INTERNAL, it) }
    }

    private fun handle(infoHashHex: String): TorrentHandle? =
        handles[infoHashHex.lowercase()]?.takeIf { it.isValid() }

    private fun control(infoHashHex: String, block: (TorrentHandle) -> Unit): Result<Unit> {
        val handle = handle(infoHashHex)
            ?: return Result.failure(EngineFailure(EngineError.UNKNOWN_TORRENT))
        return runCatching { block(handle) }.mapCatching { }
            .recoverCatching { throw EngineFailure(EngineError.INTERNAL, it) }
    }

    private fun TorrentStatus.toTaskStatus(hex: String): TaskStatus = TaskStatus(
        infoHash = hex,
        state = stateLabel(),
        progress = progress().toDouble(),
        downloadedBytes = totalDone(),
        totalBytes = total(),
        downloadBps = downloadRate().toLong(),
        uploadBps = uploadRate().toLong(),
        numPeers = numPeers(),
        numSeeds = numSeeds(),
        errorMessage = errorCode().takeIf { it.isError }?.message,
    )

    private fun Long.coerceToInt(): Int = coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()
}
