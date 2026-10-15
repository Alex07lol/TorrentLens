package dev.torrentlens.core.reader

/**
 * Plain-text reading without loading a whole file into a single UI string.
 *
 * The text is split into pages on paragraph boundaries so a large log or book
 * does not become one unbounded `Text` node, and page turns stay O(1).
 */
class TextDocumentSource(private val text: String, val targetCharsPerPage: Int = 2_000) {

    val pages: List<String> by lazy { paginate() }

    val pageCount: Int get() = pages.size

    /** First line of the file, used as a fallback title. */
    val suggestedTitle: String?
        get() = text.lineSequence().firstOrNull { it.isNotBlank() }?.trim()?.take(120)

    private fun paginate(): List<String> {
        if (text.isEmpty()) return listOf("")
        val result = mutableListOf<String>()
        val builder = StringBuilder()
        fun flush() {
            if (builder.isNotEmpty()) {
                result += builder.toString().trimEnd()
                builder.clear()
            }
        }

        for (paragraph in text.split("\n\n")) {
            if (paragraph.length > targetCharsPerPage) {
                // A single huge paragraph: hard-wrap it so one page cannot blow
                // past the limit.
                paragraph.chunked(targetCharsPerPage).forEach { chunk ->
                    flush()
                    result += chunk
                }
                continue
            }
            // Account for the "\n\n" separator this paragraph would add, so the
            // emitted page never exceeds the requested size.
            val projected = builder.length + paragraph.length + if (builder.isEmpty()) 0 else 2
            if (builder.isNotEmpty() && projected > targetCharsPerPage) flush()
            if (builder.isNotEmpty()) builder.append("\n\n")
            builder.append(paragraph)
        }
        flush()
        return result.ifEmpty { listOf("") }
    }

    companion object {
        /** Guards against opening a multi-hundred-megabyte "text" file. */
        const val MAX_BYTES = 8 * 1024 * 1024

        fun from(bytes: ByteArray): Result<TextDocumentSource> = runCatching {
            require(bytes.size <= MAX_BYTES) { "Text file is larger than ${MAX_BYTES / 1024 / 1024} MiB" }
            TextDocumentSource(bytes.toString(Charsets.UTF_8))
        }
    }
}
