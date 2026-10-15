package dev.torrentlens.app.data

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import dev.torrentlens.core.domain.model.LibraryItem
import dev.torrentlens.core.domain.model.MediaKind
import dev.torrentlens.core.reader.ComicArchive
import dev.torrentlens.core.reader.EpubPublication
import dev.torrentlens.core.reader.PdfPageSource
import dev.torrentlens.core.reader.TextDocumentSource
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Opens a library item into something renderable.
 *
 * Archive-format readers (CBZ/CBR/EPUB) and PDF need a real, seekable file, so
 * documents opened through the Storage Access Framework are copied into the
 * app's cache first, bounded by [MAX_LOCAL_COPY_BYTES].
 */
class ReaderContentLoader(
    private val context: Context,
    private val cacheRoot: File,
) {

    sealed interface Content {
        val title: String?
    }

    data class ComicContent(
        val archive: ComicArchive,
        override val title: String?,
    ) : Content

    data class PdfContent(val source: PdfPageSource, override val title: String?) : Content

    data class TextContent(val source: TextDocumentSource, override val title: String?) : Content

    data class EpubContent(val publication: EpubPublication, override val title: String?) : Content

    data class ImageContent(val bitmap: android.graphics.Bitmap, override val title: String?) : Content

    suspend fun load(item: LibraryItem, maxImageWidthPx: Int = 2048): Result<Content> =
        withContext(Dispatchers.IO) {
            runCatching {
                when (item.kind) {
                    MediaKind.CBZ, MediaKind.CBR -> {
                        val file = localCopy(item)
                        val archive = ComicArchive.open(file).getOrThrow()
                        ComicContent(archive, item.title)
                    }
                    MediaKind.EPUB -> {
                        val file = localCopy(item)
                        val publication = EpubPublication.open(file).getOrThrow()
                        EpubContent(publication, publication.title ?: item.title)
                    }
                    MediaKind.PDF -> {
                        val descriptor = context.contentResolver
                            .openFileDescriptor(Uri.parse(item.contentUri), "r")
                            ?: error("Could not open the PDF")
                        val source = PdfPageSource.open(descriptor).getOrThrow()
                        PdfContent(source, item.title)
                    }
                    MediaKind.TEXT -> {
                        val bytes = readBytes(item)
                        TextContent(TextDocumentSource.from(bytes).getOrThrow(), item.title)
                    }
                    MediaKind.IMAGE -> {
                        val bitmap = decodeSampled(item, maxImageWidthPx)
                        ImageContent(bitmap, item.title)
                    }
                    MediaKind.HTML_BUNDLE, MediaKind.UNKNOWN ->
                        error("This file type cannot be opened by the built-in reader.")
                }
            }
        }

    private fun localCopy(item: LibraryItem): File {
        val target = File(cacheRoot, item.id.replace('/', '_'))
        if (target.exists() && target.length() > 0) return target
        val uri = Uri.parse(item.contentUri)
        context.contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "Could not open ${item.title}" }
            target.outputStream().use { output ->
                val buffer = ByteArray(1 shl 16)
                var written = 0L
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    written += read
                    require(written <= MAX_LOCAL_COPY_BYTES) { "Document is larger than the local copy limit" }
                    output.write(buffer, 0, read)
                }
            }
        }
        return target
    }

    private fun readBytes(item: LibraryItem): ByteArray {
        val uri = Uri.parse(item.contentUri)
        return context.contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "Could not open ${item.title}" }
            val bytes = input.readBytes()
            require(bytes.size <= TextDocumentSource.MAX_BYTES) { "Text file is too large to open" }
            bytes
        }
    }

    private fun decodeSampled(item: LibraryItem, maxWidthPx: Int): android.graphics.Bitmap {
        val uri = Uri.parse(item.contentUri)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (bounds.outWidth / sample > maxWidthPx) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        return context.contentResolver.openInputStream(uri).use { stream ->
            BitmapFactory.decodeStream(stream, null, options)
        } ?: error("Could not decode ${item.title}")
    }

    companion object {
        /** 1 GiB: large enough for comics and PDFs, small enough to bound cache use. */
        const val MAX_LOCAL_COPY_BYTES = 1L * 1024 * 1024 * 1024
    }
}
