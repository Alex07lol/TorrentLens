package dev.torrentlens.core.reader

import dev.torrentlens.core.domain.model.MediaKind

/**
 * Decides which reader to open based on the file name, falling back to a content
 * type. Extension wins because a provider-supplied MIME type is frequently
 * `application/octet-stream` for exactly the formats we care about.
 */
object ReaderFormatDetector {

    private val IMAGE_EXTENSIONS = setOf("jpg", "jpeg", "png", "webp", "gif", "bmp", "avif", "heic")
    private val TEXT_EXTENSIONS = setOf("txt", "md", "log", "csv", "json", "xml", "html", "htm")

    /** True when the app can open the file at all. */
    fun detect(displayName: String, mimeType: String? = null): MediaKind {
        val extension = displayName.substringAfterLast('.', "").lowercase()
        return when (extension) {
            "epub" -> MediaKind.EPUB
            "pdf" -> MediaKind.PDF
            "cbz" -> MediaKind.CBZ
            "cbr" -> MediaKind.CBR
            "zip" -> if (mimeType == "application/epub+zip") MediaKind.EPUB else MediaKind.CBZ
            "txt", "md", "log" -> MediaKind.TEXT
            else -> when {
                extension == "html" || extension == "htm" -> MediaKind.TEXT
                extension in IMAGE_EXTENSIONS -> MediaKind.IMAGE
                extension in TEXT_EXTENSIONS -> MediaKind.TEXT
                mimeType == "application/epub+zip" -> MediaKind.EPUB
                mimeType == "application/pdf" -> MediaKind.PDF
                mimeType?.startsWith("image/") == true -> MediaKind.IMAGE
                mimeType?.startsWith("text/") == true -> MediaKind.TEXT
                else -> MediaKind.UNKNOWN
            }
        }
    }

    /** Formats we can currently open, used to gate the UI's empty states. */
    fun isOpenable(kind: MediaKind): Boolean = kind != MediaKind.UNKNOWN
}
