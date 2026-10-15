package dev.torrentlens.torrentlens.torrent

import org.libtorrent4j.Priority
import org.libtorrent4j.TorrentHandle
import org.libtorrent4j.TorrentInfo

/**
 * A point-in-time measurement of what a play-while-downloading session could
 * read from disk right now.
 *
 * This is deliberately *measurement only* — no policy. How many contiguous
 * bytes are needed before playback may start, and when to slide the window, are
 * decisions made on the Dart side, where they are unit-tested without a device.
 */
data class StreamSnapshot(
    val infoHash: String,
    val relativePath: String,
    val fileIndex: Int,
    val fileLengthBytes: Long,
    val fileOffsetInTorrent: Long,
    val pieceLength: Int,
    val firstFilePiece: Int,
    val lastFilePiece: Int,
    val fileDoneBytes: Long,
    val fileComplete: Boolean,
    val rangeFirstPiece: Int,
    val rangeLastPiece: Int,
    /** Pieces in the requested range that are already on disk. */
    val piecesHave: List<Int>,
    val downloadBps: Long,
    val uploadBps: Long,
    val numPeers: Int,
    val numSeeds: Int,
    val state: String,
    val progress: Double,
)

/**
 * Reads the state a streaming session needs and applies its piece priorities.
 *
 * Priorities are graded by distance from the playhead: the piece under the
 * playhead gets the shortest deadline and each following piece a step longer, so
 * the window downloads in order instead of racing. Deadlines are relative
 * milliseconds, which is what `TorrentHandle.setPieceDeadline` expects.
 *
 * Only one streaming window is active per torrent at a time; applying a new
 * window clears the previous deadlines for that torrent. That is a real
 * limitation of this design and is documented in docs/media-support.md.
 */
internal object StreamQuery {

    /**
     * Upper bound on the pieces a single call will inspect. Keeps the platform
     * channel payload bounded on torrents with small pieces and a large
     * read-ahead window.
     */
    const val MAX_RANGE_PIECES = 512

    /** Extra time allowed beyond the graded deadline, clamp for the far edge. */
    const val MAX_DEADLINE_MS = 60_000

    /** Resolves a sanitized relative path to the engine's own file index. */
    fun resolveFileIndex(info: TorrentInfo, relativePath: String): Int? {
        val files = info.files()
        for (index in 0 until files.numFiles()) {
            val candidate = TorrentFileListSanitizer.sanitizeEntryName(files.filePath(index))
            if (candidate == relativePath) return index
        }
        return null
    }

    /** Clamps a requested piece range to the torrent, or null when empty. */
    fun clampRange(info: TorrentInfo, firstPiece: Int, lastPiece: Int): IntRange? {
        val last = info.numPieces() - 1
        if (last < 0) return null
        val first = firstPiece.coerceAtLeast(0).coerceAtMost(last)
        val clampedLast = lastPiece.coerceIn(first, last)
        val capped = minOf(clampedLast, first + MAX_RANGE_PIECES - 1)
        return first..capped
    }

    fun snapshot(
        handle: TorrentHandle,
        info: TorrentInfo,
        infoHash: String,
        relativePath: String,
        fileIndex: Int,
        range: IntRange,
    ): StreamSnapshot {
        val files = info.files()
        val fileLength = files.fileSize(fileIndex)
        val fileOffset = files.fileOffset(fileIndex)
        val pieceLength = info.pieceLength().coerceAtLeast(1)
        val firstFilePiece = (fileOffset / pieceLength).toInt()
        val lastFilePiece = ((fileOffset + fileLength.coerceAtLeast(1) - 1) / pieceLength).toInt()
        val fileDone = handle.fileProgress().getOrNull(fileIndex) ?: 0L
        val status = handle.status()

        return StreamSnapshot(
            infoHash = infoHash,
            relativePath = relativePath,
            fileIndex = fileIndex,
            fileLengthBytes = fileLength,
            fileOffsetInTorrent = fileOffset,
            pieceLength = pieceLength,
            firstFilePiece = firstFilePiece,
            lastFilePiece = lastFilePiece,
            fileDoneBytes = fileDone,
            // A zero-length file is trivially "complete": nothing to fetch.
            fileComplete = fileLength <= 0 || fileDone >= fileLength,
            rangeFirstPiece = range.first,
            rangeLastPiece = range.last,
            piecesHave = range.filter { handle.havePiece(it) },
            downloadBps = status.downloadRate().toLong(),
            uploadBps = status.uploadRate().toLong(),
            numPeers = status.numPeers(),
            numSeeds = status.numSeeds(),
            state = status.stateLabel(),
            progress = status.progress().toDouble(),
        )
    }

    /**
     * Raises the streamed file and the window pieces to top priority and sets
     * graded deadlines so the window arrives in playback order.
     *
     * Raising the *file* priority is what makes streaming a deselected file
     * possible; the caller restores the user's selection when playback ends.
     * Setting piece priorities explicitly means the window downloads even when
     * the rest of the file stays at its previous priority.
     */
    fun applyPriority(
        handle: TorrentHandle,
        fileIndex: Int,
        range: IntRange,
        baseDeadlineMs: Int,
        stepMs: Int,
    ) {
        handle.clearPieceDeadlines()
        handle.filePriority(fileIndex, Priority.TOP_PRIORITY)
        range.forEach { piece ->
            val distance = piece - range.first
            val deadline = (baseDeadlineMs + distance * stepMs).coerceAtMost(MAX_DEADLINE_MS)
            handle.piecePriority(piece, Priority.TOP_PRIORITY)
            handle.setPieceDeadline(piece, deadline)
        }
    }

    /** Releases a stream: drops deadlines and restores the previous priority. */
    fun releasePriority(handle: TorrentHandle, fileIndex: Int, previous: Priority) {
        handle.clearPieceDeadlines()
        handle.filePriority(fileIndex, previous)
    }
}
