package dev.torrentlens.core.reader

import dev.torrentlens.core.domain.security.SafePaths
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.ZipFile

/**
 * Page access for CBZ and CBR archives.
 *
 * Entry names are attacker-controlled, so every name is normalised through
 * [SafePaths.sanitizeEntryName] and anything that escapes is dropped rather than
 * shown. Pages are read on demand rather than extracted, so opening a large
 * archive is cheap and nothing is written to disk.
 */
sealed interface ComicArchive : AutoCloseable {

    val pageCount: Int

    /** Relative, already-sanitised entry name for the page at [index]. */
    fun pageName(index: Int): String

    fun readPage(index: Int): ByteArray

    companion object {
        private val IMAGE_EXTENSIONS = setOf("jpg", "jpeg", "png", "webp", "gif", "bmp", "avif")

        fun open(file: File): Result<ComicArchive> {
            val name = file.name.lowercase()
            return when {
                name.endsWith(".cbz") || name.endsWith(".zip") -> CbzArchive.open(file)
                name.endsWith(".cbr") -> RarComicArchive.open(file)
                else -> Result.failure(UnsupportedArchiveException("Unsupported comic archive: ${file.name}"))
            }
        }

        internal fun isImageEntry(name: String): Boolean {
            if (name.endsWith("/")) return false
            val base = name.substringAfterLast('/')
            if (base.startsWith(".")) return false
            val extension = base.substringAfterLast('.', "").lowercase()
            return extension in IMAGE_EXTENSIONS
        }
    }
}

class UnsupportedArchiveException(message: String) : Exception(message)

/** CBZ is a plain ZIP; the JDK handles it. */
internal class CbzArchive private constructor(
    private val zip: ZipFile,
    private val pages: List<String>,
) : ComicArchive {

    override val pageCount: Int get() = pages.size

    override fun pageName(index: Int): String = pages[index]

    override fun readPage(index: Int): ByteArray {
        val entry = zip.getEntry(pages[index])
            ?: throw IllegalStateException("Missing archive entry: ${pages[index]}")
        return zip.getInputStream(entry).use { it.readBytes() }
    }

    override fun close() = zip.close()

    companion object {
        fun open(file: File): Result<ComicArchive> = runCatching {
            val zip = ZipFile(file)
            val pages = zip.entries().asSequence()
                .map { it.name }
                .filter { ComicArchive.isImageEntry(it) }
                .mapNotNull { SafePaths.sanitizeEntryName(it) }
                .sortedWith { a, b -> NaturalOrder.comparePaths(a, b) }
                .toList()
            if (pages.isEmpty()) {
                zip.close()
                throw UnsupportedArchiveException("No images found in ${file.name}")
            }
            CbzArchive(zip, pages)
        }
    }
}

/**
 * CBR support. junrar is under the UnRAR licence; it is allowed to *extract*
 * RAR archives but cannot be used to build a RAR compressor. It is isolated in
 * `:core:reader` so a distribution that cannot accept that licence can drop this
 * one file without touching anything else.
 */
internal class RarComicArchive private constructor(
    private val archive: com.github.junrar.Archive,
    private val headers: List<com.github.junrar.rarfile.FileHeader>,
    private val pages: List<String>,
) : ComicArchive {

    override val pageCount: Int get() = pages.size

    override fun pageName(index: Int): String = pages[index]

    override fun readPage(index: Int): ByteArray {
        val header = headers.firstOrNull { SafePaths.sanitizeEntryName(it.fileName) == pages[index] }
            ?: throw IllegalStateException("Missing archive entry: ${pages[index]}")
        val out = ByteArrayOutputStream()
        archive.extractFile(header, out)
        return out.toByteArray()
    }

    override fun close() = archive.close()

    companion object {
        fun open(file: File): Result<ComicArchive> = runCatching {
            val archive = com.github.junrar.Archive(file)
            val headers = archive.fileHeaders
                .filter { !it.isDirectory && ComicArchive.isImageEntry(it.fileName) }
            val pages = headers
                .mapNotNull { SafePaths.sanitizeEntryName(it.fileName) }
                .distinct()
                .sortedWith { a, b -> NaturalOrder.comparePaths(a, b) }
            if (pages.isEmpty()) {
                archive.close()
                throw UnsupportedArchiveException("No images found in ${file.name}")
            }
            RarComicArchive(archive, headers, pages)
        }
    }
}
