package dev.torrentlens.core.reader

import dev.torrentlens.core.domain.model.MediaKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReaderLogicTest {

    // ---- format detection -------------------------------------------------

    @Test
    fun `detects formats by extension`() {
        assertEquals(MediaKind.EPUB, ReaderFormatDetector.detect("book.epub"))
        assertEquals(MediaKind.PDF, ReaderFormatDetector.detect("doc.PDF"))
        assertEquals(MediaKind.CBZ, ReaderFormatDetector.detect("comic.cbz"))
        assertEquals(MediaKind.CBR, ReaderFormatDetector.detect("comic.cbr"))
        assertEquals(MediaKind.IMAGE, ReaderFormatDetector.detect("art/pic.webp"))
        assertEquals(MediaKind.TEXT, ReaderFormatDetector.detect("notes.txt"))
        assertEquals(MediaKind.UNKNOWN, ReaderFormatDetector.detect("binary.bin"))
    }

    @Test
    fun `falls back to mime type when the extension is unhelpful`() {
        assertEquals(MediaKind.EPUB, ReaderFormatDetector.detect("download", "application/epub+zip"))
        assertEquals(MediaKind.IMAGE, ReaderFormatDetector.detect("download", "image/png"))
    }

    // ---- archive path resolution (EPUB hrefs) -----------------------------

    @Test
    fun `resolves sibling and parent references inside the archive`() {
        assertEquals("OEBPS/text/ch1.xhtml", ArchivePath.resolve("OEBPS/text", "ch1.xhtml"))
        assertEquals("OEBPS/images/cover.jpg", ArchivePath.resolve("OEBPS/text", "../images/cover.jpg"))
        assertEquals("styles/main.css", ArchivePath.resolve("OEBPS/text", "../../styles/main.css"))
    }

    @Test
    fun `refuses to walk out of the archive root`() {
        assertNull(ArchivePath.resolve("OEBPS", "../../../etc/passwd"))
        assertNull(ArchivePath.resolve("", "../../evil"))
    }

    @Test
    fun `strips fragments and query strings and decodes percent escapes`() {
        assertEquals("OEBPS/text/ch1.xhtml", ArchivePath.resolve("OEBPS/text", "ch1.xhtml#section-2"))
        assertEquals("OEBPS/text/ch 1.xhtml", ArchivePath.resolve("OEBPS/text", "ch%201.xhtml"))
    }

    // ---- comic page ordering ---------------------------------------------

    @Test
    fun `orders comic pages naturally rather than lexicographically`() {
        val pages = listOf("p10.jpg", "p2.jpg", "p1.jpg", "p20.jpg")
        val sorted = pages.sortedWith { a, b -> NaturalOrder.comparePaths(a, b) }
        assertEquals(listOf("p1.jpg", "p2.jpg", "p10.jpg", "p20.jpg"), sorted)
    }

    @Test
    fun `compares only the last path segment`() {
        assertEquals(0, NaturalOrder.comparePaths("deep/dir/page1.jpg", "page1.jpg"))
        assertTrue(NaturalOrder.comparePaths("a/2.jpg", "a/10.jpg") < 0)
    }

    // ---- text pagination --------------------------------------------------

    @Test
    fun `paginates long text without one unbounded page`() {
        val paragraph = "x".repeat(500)
        val source = TextDocumentSource(List(20) { paragraph }.joinToString("\n\n"), targetCharsPerPage = 1_000)
        assertTrue(source.pageCount > 1)
        assertTrue(source.pages.all { it.length <= 1_000 })
    }

    @Test
    fun `suggests a title from the first non-blank line`() {
        assertEquals("My Journal", TextDocumentSource("\n\nMy Journal\n\nbody").suggestedTitle)
    }
}
