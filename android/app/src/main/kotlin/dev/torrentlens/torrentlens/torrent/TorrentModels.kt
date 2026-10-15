package dev.torrentlens.torrentlens.torrent

import java.io.File

/** Session-wide configuration applied when the engine starts. */
data class EngineOptions(
    val sessionDownloadLimitBytesPerSec: Long = 0,
    val sessionUploadLimitBytesPerSec: Long = 0,
    val enableDht: Boolean = true,
    val maxActiveDownloads: Int = 3,
    val listenPort: Int = 0,
)

/** Engine failures translated into user-actionable messages. */
enum class EngineError(val message: String) {
    NOT_STARTED("The torrent engine is not running."),
    METADATA_TIMEOUT("Could not fetch torrent metadata from peers or the DHT in time."),
    UNKNOWN_TORRENT("That torrent is no longer in the engine."),
    INVALID_DESCRIPTOR("That .torrent file could not be read."),
    DUPLICATE("That torrent is already in the list."),
    FILE_NOT_FOUND("That file is not part of this torrent's current file list."),
    INTERNAL("The torrent engine reported an error."),
}

class EngineFailure(val error: EngineError, cause: Throwable? = null) :
    Exception(error.message, cause)

/** A validated file-list entry. */
data class SafeTorrentFile(
    val originalPath: String,
    val relativePath: String,
    val lengthBytes: Long,
    val isPaddingFile: Boolean,
)

enum class FileRejectionReason {
    EMPTY_NAME, NULL_BYTE, ABSOLUTE_PATH, PATH_TRAVERSAL, NAME_TOO_LONG, NEGATIVE_LENGTH, DUPLICATE_PATH,
}

data class RejectedFile(val originalPath: String, val reason: FileRejectionReason)

/**
 * Validates a torrent's advertised file list *before* the engine writes
 * anything. The list is attacker-controlled (it comes from remote peers), so a
 * hostile torrent must not be able to escape the chosen download directory.
 */
object TorrentFileListSanitizer {

    private const val MAX_NAME_BYTES = 4096

    fun sanitize(
        rawPaths: List<Pair<String, Long>>,
        paddingFlags: List<Boolean> = emptyList(),
    ): Pair<List<SafeTorrentFile>, List<RejectedFile>> {
        val accepted = mutableListOf<SafeTorrentFile>()
        val rejected = mutableListOf<RejectedFile>()
        val seen = HashSet<String>(rawPaths.size)

        rawPaths.forEachIndexed { index, (raw, length) ->
            val isPadding = paddingFlags.getOrElse(index) { false }
            val reason = when {
                raw.isBlank() -> FileRejectionReason.EMPTY_NAME
                raw.contains('\u0000') -> FileRejectionReason.NULL_BYTE
                raw.toByteArray(Charsets.UTF_8).size > MAX_NAME_BYTES -> FileRejectionReason.NAME_TOO_LONG
                length < 0 -> FileRejectionReason.NEGATIVE_LENGTH
                raw.replace('\\', '/').startsWith("/") ||
                    Regex("^[A-Za-z]:").containsMatchIn(raw) -> FileRejectionReason.ABSOLUTE_PATH
                else -> null
            }
            if (reason != null) {
                rejected += RejectedFile(raw, reason)
                return@forEachIndexed
            }
            val safe = sanitizeEntryName(raw)
            if (safe == null) {
                rejected += RejectedFile(raw, FileRejectionReason.PATH_TRAVERSAL)
            } else if (!seen.add(safe)) {
                rejected += RejectedFile(raw, FileRejectionReason.DUPLICATE_PATH)
            } else {
                accepted += SafeTorrentFile(raw, safe, length, isPadding)
            }
        }
        return accepted to rejected
    }

    /** Normalises `a/./b/../c` to `a/c` and rejects any escaping component. */
    fun sanitizeEntryName(raw: String): String? {
        val parts = mutableListOf<String>()
        for (segment in raw.replace('\\', '/').split('/')) {
            when {
                segment.isEmpty() || segment == "." -> {}
                segment == ".." -> {
                    if (parts.isEmpty()) return null
                    parts.removeAt(parts.size - 1)
                }
                else -> parts += segment
            }
        }
        return if (parts.isEmpty()) null else parts.joinToString("/")
    }

    fun ensureDirectory(dir: File) {
        if (!dir.exists()) dir.mkdirs()
    }
}
