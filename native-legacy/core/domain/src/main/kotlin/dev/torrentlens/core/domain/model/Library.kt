package dev.torrentlens.core.domain.model

/** The kinds of content the built-in reader can open. */
enum class MediaKind {
    EPUB,
    PDF,
    CBZ,
    CBR,
    IMAGE,
    TEXT,
    HTML_BUNDLE,
    UNKNOWN,
    ;

    /** Formats we advertise as supported; CBR depends on the UnRAR-licensed module. */
    val isComic: Boolean get() = this == CBZ || this == CBR
    val isBook: Boolean get() = this == EPUB
}

/** Page layout preference, including RTL manga mode. */
enum class ReadingMode { PAGED, VERTICAL_SCROLL }

enum class ReadingDirection { LEFT_TO_RIGHT, RIGHT_TO_LEFT }

data class LibraryItem(
    val id: String,
    val title: String,
    val kind: MediaKind,
    /** `content://` URI of the original file, or of the extracted directory. */
    val contentUri: String,
    val sizeBytes: Long,
    val addedAtEpochMillis: Long,
    val sourceTaskId: String? = null,
    val coverPath: String? = null,
)

data class ReadingProgress(
    val libraryItemId: String,
    /** EPUB: spine href. Comic/PDF: page index as a string. */
    val locator: String,
    val percent: Double,
    val updatedAtEpochMillis: Long,
    val mode: ReadingMode = ReadingMode.PAGED,
    val direction: ReadingDirection = ReadingDirection.LEFT_TO_RIGHT,
)

data class Bookmark(
    val id: String,
    val libraryItemId: String,
    val locator: String,
    val label: String?,
    val createdAtEpochMillis: Long,
)
