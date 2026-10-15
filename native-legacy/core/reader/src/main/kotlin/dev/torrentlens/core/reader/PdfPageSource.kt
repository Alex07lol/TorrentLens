package dev.torrentlens.core.reader

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor

/**
 * PDF rendering on the platform `PdfRenderer`.
 *
 * One page is rendered at a time and the caller owns the resulting bitmap, so
 * there is no unbounded per-document memory growth on a phone. The descriptor
 * must be seekable, which is true for documents opened through the Storage
 * Access Framework.
 */
class PdfPageSource private constructor(private val renderer: PdfRenderer) : AutoCloseable {

    val pageCount: Int get() = renderer.pageCount

    /** Renders [index] at [targetWidthPx], preserving aspect ratio. */
    fun render(index: Int, targetWidthPx: Int): Bitmap {
        require(index in 0 until pageCount) { "Page $index out of range (0..${pageCount - 1})" }
        renderer.openPage(index).use { page ->
            val width = targetWidthPx.coerceAtLeast(1)
            val height = (width.toFloat() * page.height / page.width).toInt().coerceAtLeast(1)
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            // PdfRenderer leaves untouched pixels transparent; fill with white so
            // dark themes invert predictably instead of showing black.
            bitmap.eraseColor(Color.WHITE)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            return bitmap
        }
    }

    fun pageAspectRatio(index: Int): Float {
        require(index in 0 until pageCount)
        renderer.openPage(index).use { page -> return page.width.toFloat() / page.height.toFloat() }
    }

    override fun close() = renderer.close()

    companion object {
        fun open(descriptor: ParcelFileDescriptor): Result<PdfPageSource> = runCatching {
            // PdfRenderer takes ownership of the descriptor.
            PdfPageSource(PdfRenderer(descriptor))
        }
    }
}
