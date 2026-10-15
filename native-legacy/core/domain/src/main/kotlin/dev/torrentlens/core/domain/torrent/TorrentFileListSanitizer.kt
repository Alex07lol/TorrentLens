package dev.torrentlens.core.domain.torrent

import dev.torrentlens.core.domain.security.SafePaths

/** One entry of a torrent's file list, as reported by the engine's metadata. */
data class RawTorrentFile(
    val path: String,
    val lengthBytes: Long,
    val isPaddingFile: Boolean = false,
)

/** A file list entry that survived validation. */
data class SafeTorrentFile(
    val originalPath: String,
    val relativePath: String,
    val lengthBytes: Long,
    val isPaddingFile: Boolean,
)

enum class FileRejectionReason {
    EMPTY_NAME,
    NULL_BYTE,
    ABSOLUTE_PATH,
    PATH_TRAVERSAL,
    NAME_TOO_LONG,
    NEGATIVE_LENGTH,
    DUPLICATE_PATH,
}

data class RejectedFile(val originalPath: String, val reason: FileRejectionReason)

data class TorrentFileList(
    val accepted: List<SafeTorrentFile>,
    val rejected: List<RejectedFile>,
) {
    val totalBytes: Long get() = accepted.sumOf { it.lengthBytes }
    val isFullyClean: Boolean get() = rejected.isEmpty()
}

/**
 * Validates the file list a torrent advertises.
 *
 * This runs *before* the engine is asked to write anything. The list comes from
 * remote peers and is fully attacker-controlled, so a hostile torrent must not be
 * able to escape the chosen download directory or overwrite unrelated files.
 */
object TorrentFileListSanitizer {

    fun sanitize(files: List<RawTorrentFile>, maxNameBytes: Int = 4096): TorrentFileList {
        val accepted = mutableListOf<SafeTorrentFile>()
        val rejected = mutableListOf<RejectedFile>()
        val seen = HashSet<String>(files.size)

        for (file in files) {
            val raw = file.path
            val reason = when {
                raw.isBlank() -> FileRejectionReason.EMPTY_NAME
                raw.any { it == '\u0000' } -> FileRejectionReason.NULL_BYTE
                !SafePaths.isLengthAcceptable(raw, maxNameBytes) -> FileRejectionReason.NAME_TOO_LONG
                file.lengthBytes < 0 -> FileRejectionReason.NEGATIVE_LENGTH
                raw.replace('\\', '/').startsWith("/") ||
                    Regex("^[A-Za-z]:").containsMatchIn(raw) -> FileRejectionReason.ABSOLUTE_PATH
                else -> null
            }
            if (reason != null) {
                rejected += RejectedFile(raw, reason)
                continue
            }

            val safe = SafePaths.sanitizeEntryName(raw)
            if (safe == null) {
                rejected += RejectedFile(raw, FileRejectionReason.PATH_TRAVERSAL)
                continue
            }
            if (!seen.add(safe)) {
                rejected += RejectedFile(raw, FileRejectionReason.DUPLICATE_PATH)
                continue
            }
            accepted += SafeTorrentFile(
                originalPath = raw,
                relativePath = safe,
                lengthBytes = file.lengthBytes,
                isPaddingFile = file.isPaddingFile,
            )
        }

        return TorrentFileList(accepted, rejected)
    }
}
