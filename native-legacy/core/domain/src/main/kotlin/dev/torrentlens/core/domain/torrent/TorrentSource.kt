package dev.torrentlens.core.domain.torrent

/**
 * Everything the torrent client can be asked to open. Modelled as a closed
 * hierarchy so the import UI cannot hand the engine an unvalidated string.
 */
sealed interface TorrentSource {
    /** Parsed magnet URI. */
    data class Magnet(val uri: MagnetUri, val original: String) : TorrentSource

    /** A remote `.torrent` (or server-side generated) descriptor over HTTP(S). */
    data class Remote(val url: String) : TorrentSource

    /** A local `.torrent` file the user picked, either via SAF or a real path. */
    data class LocalFile(val displayName: String, val location: String) : TorrentSource

    /** Raw bencoded `.torrent` bytes already read into memory. */
    data class Bytes(val displayName: String, val content: ByteArray) : TorrentSource {
        override fun equals(other: Any?): Boolean =
            this === other ||
                (other is Bytes && displayName == other.displayName && content.contentEquals(other.content))

        override fun hashCode(): Int = 31 * displayName.hashCode() + content.contentHashCode()
    }
}

/** Classifies a pasted/typed string into a [TorrentSource] without side effects. */
object TorrentSourceClassifier {

    private val SCHEME = Regex("^[a-zA-Z][a-zA-Z0-9+.-]*:")

    fun classify(input: String): Result<TorrentSource> {
        val text = input.trim()
        if (text.isEmpty()) return Result.failure(TorrentInputException(TorrentInputError.Empty))

        if (text.startsWith("magnet:", ignoreCase = true)) {
            return when (val r = MagnetUri.parse(text)) {
                is MagnetUri.ParseResult.Valid -> Result.success(TorrentSource.Magnet(r.magnet, text))
                is MagnetUri.ParseResult.Invalid -> Result.failure(
                    TorrentInputException(
                        when (r.error) {
                            MagnetUri.MagnetError.MISSING_INFO_HASH -> TorrentInputError.MagnetMissingInfoHash
                            MagnetUri.MagnetError.MALFORMED_INFO_HASH -> TorrentInputError.MagnetMalformedInfoHash
                            else -> TorrentInputError.MagnetUnsupportedHash
                        },
                    ),
                )
            }
        }

        if (text.startsWith("content://", ignoreCase = true) ||
            text.startsWith("file://", ignoreCase = true)
        ) {
            return Result.success(TorrentSource.LocalFile(displayNameOf(text), text))
        }

        if (text.startsWith("http://", true) || text.startsWith("https://", true)) {
            return if (isPlausibleHttpUrl(text)) {
                Result.success(TorrentSource.Remote(stripFragment(text)))
            } else {
                Result.failure(TorrentInputException(TorrentInputError.MalformedUrl))
            }
        }

        // Reject anything else that looks like it has an unsupported scheme
        // (javascript:, data:, intent:, ...) instead of treating it as a path.
        if (SCHEME.containsMatchIn(text)) return Result.failure(TorrentInputException(TorrentInputError.UnsupportedScheme))

        return if (text.endsWith(".torrent", ignoreCase = true)) {
            Result.success(TorrentSource.LocalFile(displayNameOf(text), text))
        } else {
            Result.failure(TorrentInputException(TorrentInputError.UnrecognizedInput))
        }
    }

    private fun displayNameOf(location: String): String =
        location.substringAfterLast('/').substringBefore('?').ifBlank { "download.torrent" }

    private fun stripFragment(url: String): String = url.substringBefore('#')

    /**
     * Minimal structural check. Full validation happens at fetch time; this only
     * rejects obvious junk so the UI can fail fast with a useful message.
     */
    private fun isPlausibleHttpUrl(url: String): Boolean {
        val afterScheme = url.substringAfter("://", "")
        if (afterScheme.isEmpty()) return false
        val authority = afterScheme.substringBefore('/').substringBefore('?')
        if (authority.isEmpty()) return false
        if (authority.any { it == ' ' || it == '\n' || it == '\t' }) return false
        val host = authority.substringAfter('@').substringBefore(':')
        return host.isNotEmpty() && (host.contains('.') || host == "localhost")
    }
}

/**
 * Why a piece of pasted text could not be turned into a [TorrentSource].
 * A plain enum (not an Exception) so callers can branch on it exhaustively;
 * [TorrentInputException] is the throwable form used with `Result.failure`.
 */
enum class TorrentInputError(val message: String) {
    Empty("No magnet link, torrent URL, or file was provided."),
    MagnetMissingInfoHash("This magnet link has no info-hash, so the torrent cannot be identified."),
    MagnetMalformedInfoHash("The magnet link's info-hash is not a valid 40-character hex or 32-character base32 value."),
    MagnetUnsupportedHash("This magnet link uses a hash type TorrentLens does not support."),
    UnsupportedScheme("Only magnet links, http(s) torrent URLs, and local .torrent files are supported."),
    MalformedUrl("That torrent URL does not look valid."),
    UnrecognizedInput("Not a magnet link, torrent URL, or .torrent file."),
}

class TorrentInputException(val error: TorrentInputError) : Exception(error.message)
