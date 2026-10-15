package dev.torrentlens.core.domain.torrent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TorrentFileListSanitizerTest {

    @Test
    fun `accepts a normal multi-file torrent`() {
        val result = TorrentFileListSanitizer.sanitize(
            listOf(
                RawTorrentFile("Album/01 - track.flac", 30_000_000),
                RawTorrentFile("Album/cover.jpg", 120_000),
                RawTorrentFile("Album/notes.txt", 900),
            ),
        )
        assertEquals(3, result.accepted.size)
        assertTrue(result.isFullyClean)
        assertEquals(30_120_900L, result.totalBytes)
    }

    @Test
    fun `rejects hostile entries and keeps the safe ones`() {
        val result = TorrentFileListSanitizer.sanitize(
            listOf(
                RawTorrentFile("good/file.bin", 10),
                RawTorrentFile("../../data/data/com.app/databases/db", 10),
                RawTorrentFile("/etc/hosts", 10),
                RawTorrentFile("C:\\Windows\\evil.dll", 10),
                RawTorrentFile("good/file.bin", 10),
                RawTorrentFile("", 10),
                RawTorrentFile("negative.bin", -5),
                RawTorrentFile("nul\u0000byte", 10),
            ),
        )
        assertEquals(listOf("good/file.bin"), result.accepted.map { it.relativePath })
        val reasons = result.rejected.map { it.reason }
        assertTrue(FileRejectionReason.PATH_TRAVERSAL in reasons)
        assertTrue(FileRejectionReason.ABSOLUTE_PATH in reasons)
        assertTrue(FileRejectionReason.DUPLICATE_PATH in reasons)
        assertTrue(FileRejectionReason.EMPTY_NAME in reasons)
        assertTrue(FileRejectionReason.NEGATIVE_LENGTH in reasons)
        assertTrue(FileRejectionReason.NULL_BYTE in reasons)
        assertFalse(result.isFullyClean)
        assertEquals(10L, result.totalBytes)
    }

    @Test
    fun `padding files are preserved but flagged`() {
        val result = TorrentFileListSanitizer.sanitize(
            listOf(RawTorrentFile(".pad/0", 4096, isPaddingFile = true)),
        )
        assertTrue(result.accepted.single().isPaddingFile)
    }

    @Test
    fun `unusually long names are rejected`() {
        val result = TorrentFileListSanitizer.sanitize(listOf(RawTorrentFile("x".repeat(5000), 1)))
        assertEquals(FileRejectionReason.NAME_TOO_LONG, result.rejected.single().reason)
    }
}
