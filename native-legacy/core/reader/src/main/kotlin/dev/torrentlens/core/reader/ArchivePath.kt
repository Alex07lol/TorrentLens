package dev.torrentlens.core.reader

/**
 * Resolves a relative reference (such as an EPUB `href`) against a directory
 * inside the same archive.
 *
 * Unlike [dev.torrentlens.core.domain.security.SafePaths.sanitizeEntryName], a
 * `..` segment is *legal* here: EPUB chapter files routinely reference
 * `../styles/readium.css`. What is not legal is escaping the archive root, so
 * `..` pops the accumulated stack and a pop below zero fails.
 */
object ArchivePath {

    fun resolve(baseDir: String, href: String): String? {
        val cleanedHref = href.substringBefore('#').substringBefore('?')
        if (cleanedHref.isEmpty()) return null
        val decoded = percentDecode(cleanedHref)

        val segments = ArrayDeque<String>()
        for (segment in baseDir.replace('\\', '/').split('/')) {
            when (segment) {
                "", "." -> Unit
                ".." -> if (segments.isEmpty()) return null else segments.removeLast()
                else -> segments.addLast(segment)
            }
        }
        for (segment in decoded.replace('\\', '/').split('/')) {
            when (segment) {
                "", "." -> Unit
                ".." -> if (segments.isEmpty()) return null else segments.removeLast()
                else -> segments.addLast(segment)
            }
        }
        if (segments.isEmpty()) return null
        return segments.joinToString("/")
    }

    private fun percentDecode(value: String): String {
        if (value.indexOf('%') < 0) return value
        val out = StringBuilder(value.length)
        var i = 0
        while (i < value.length) {
            val c = value[i]
            if (c == '%' && i + 2 < value.length) {
                val hi = Character.digit(value[i + 1], 16)
                val lo = Character.digit(value[i + 2], 16)
                if (hi >= 0 && lo >= 0) {
                    out.append(((hi shl 4) or lo).toChar())
                    i += 3
                    continue
                }
            }
            out.append(c)
            i++
        }
        return out.toString()
    }
}
