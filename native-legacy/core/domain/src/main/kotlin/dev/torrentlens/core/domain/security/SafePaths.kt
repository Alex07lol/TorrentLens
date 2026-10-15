package dev.torrentlens.core.domain.security

import java.nio.file.Path

/**
 * Path-safety rules for anything that comes out of an archive or a torrent's
 * file list. Both are attacker-controlled: a hostile `.torrent` or a crafted
 * EPUB/CBZ can name a member `../../../../data/data/<pkg>/databases/app.db`, and
 * a naive `zip.extract()` would happily overwrite it ("zip-slip").
 *
 * These functions are pure and total so they can be unit-tested exhaustively.
 */
object SafePaths {

    /**
     * Normalizes a single archive/torrent entry name into a safe relative path,
     * or returns null if the entry must be rejected outright.
     *
     * Rejected: empty names, NUL bytes, absolute paths, drive/UNC prefixes, and
     * any path that traverses above its own root.
     */
    fun sanitizeEntryName(rawName: String): String? {
        if (rawName.isEmpty()) return null
        if (rawName.any { it == '\u0000' }) return null

        // Torrent and ZIP conventions both allow '\' as a separator in names
        // produced on Windows; normalize before splitting so we cannot be
        // tricked by mixing separators.
        val unified = rawName.replace('\\', '/')

        if (unified.startsWith("/")) return null                 // absolute POSIX
        if (Regex("^[A-Za-z]:").containsMatchIn(unified)) return null // drive letter
        if (unified.startsWith("//")) return null                // UNC

        val segments = mutableListOf<String>()
        for (segment in unified.split('/')) {
            when (segment) {
                "", "." -> continue
                ".." -> return null // refuse to even attempt to walk up
                else -> segments += segment
            }
        }
        if (segments.isEmpty()) return null
        return segments.joinToString("/")
    }

    /**
     * Resolves [entryName] beneath [baseDir], guaranteeing the result is a
     * descendant of [baseDir]. Returns null when the name escapes.
     *
     * Callers must still re-check with [isContainedBy] after touching the
     * filesystem, because a pre-existing symlink inside the destination can
     * redirect a write even for a lexically-safe name.
     */
    fun resolveInside(baseDir: Path, entryName: String): Path? {
        val safe = sanitizeEntryName(entryName) ?: return null
        val base = baseDir.toAbsolutePath().normalize()
        val resolved = base.resolve(safe).normalize()
        return if (resolved.startsWith(base)) resolved else null
    }

    /**
     * Post-extraction defence against symlink redirection: re-resolve the real
     * path and confirm it is still inside the destination.
     */
    fun isContainedBy(baseDir: Path, candidate: Path): Boolean {
        val base = baseDir.toAbsolutePath().normalize()
        val real = runCatching { candidate.toRealPath() }.getOrNull() ?: return false
        return real.startsWith(base)
    }

    /**
     * A single torrent entry name may not exceed this many path segments or
     * bytes; unbounded names are a cheap way to exhaust memory or a FAT32/EXFAT
     * removable volume's file-name limit.
     */
    fun isLengthAcceptable(entryName: String, maxBytes: Int = 4096): Boolean =
        entryName.toByteArray(Charsets.UTF_8).size <= maxBytes
}
