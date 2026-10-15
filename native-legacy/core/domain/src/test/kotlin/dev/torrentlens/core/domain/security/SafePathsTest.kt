package dev.torrentlens.core.domain.security

import java.nio.file.Files
import java.nio.file.Paths
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SafePathsTest {

    @Test
    fun `normalizes harmless relative paths`() {
        assertEquals("a/b/c.txt", SafePaths.sanitizeEntryName("a/b/c.txt"))
        assertEquals("a/b", SafePaths.sanitizeEntryName("./a/./b/"))
        assertEquals("a/b/c", SafePaths.sanitizeEntryName("a\\b\\c"))
        assertEquals("chapter 1/page 01.jpg", SafePaths.sanitizeEntryName("chapter 1/page 01.jpg"))
    }

    @Test
    fun `rejects traversal, absolute and prefix escapes`() {
        assertNull(SafePaths.sanitizeEntryName("../../etc/passwd"))
        assertNull(SafePaths.sanitizeEntryName("a/../../b"))
        assertNull(SafePaths.sanitizeEntryName("..\\..\\windows\\system32"))
        assertNull(SafePaths.sanitizeEntryName("/etc/passwd"))
        assertNull(SafePaths.sanitizeEntryName("C:\\Windows\\System32\\drivers\\etc\\hosts"))
        assertNull(SafePaths.sanitizeEntryName("//server/share/x"))
        assertNull(SafePaths.sanitizeEntryName(""))
        assertNull(SafePaths.sanitizeEntryName("./"))
        assertNull(SafePaths.sanitizeEntryName("a\u0000b"))
    }

    @Test
    fun `resolveInside keeps writes under the base directory`() {
        val base = Paths.get("/sdcard/TorrentLens")
        assertNotNull(SafePaths.resolveInside(base, "book/ch1.xhtml"))
        assertEquals(
            base.resolve("book/ch1.xhtml"),
            SafePaths.resolveInside(base, "book/ch1.xhtml"),
        )
        assertNull(SafePaths.resolveInside(base, "../../data/data/app/databases/db"))
    }

    @Test
    fun `isContainedBy detects a real escape`() {
        val root = Files.createTempDirectory("tl-root")
        val inside = Files.writeString(root.resolve("ok.txt"), "x")
        val outside = Files.createTempFile("tl-outside", ".txt")
        assertTrue(SafePaths.isContainedBy(root, inside))
        assertFalse(SafePaths.isContainedBy(root, outside))
    }

    @Test
    fun `name length guard uses utf8 bytes`() {
        assertTrue(SafePaths.isLengthAcceptable("short.txt"))
        assertFalse(SafePaths.isLengthAcceptable("a".repeat(5000)))
        // Multi-byte characters count as their UTF-8 width, not character count.
        assertFalse(SafePaths.isLengthAcceptable("\u00e9".repeat(2500), maxBytes = 4096))
    }
}
