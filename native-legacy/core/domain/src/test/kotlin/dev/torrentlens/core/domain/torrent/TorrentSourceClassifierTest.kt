package dev.torrentlens.core.domain.torrent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TorrentSourceClassifierTest {

    private val hex = "0123456789abcdef0123456789abcdef01234567"

    private fun failure(input: String): TorrentInputError =
        (TorrentSourceClassifier.classify(input).exceptionOrNull() as TorrentInputException).error

    @Test
    fun `classifies magnet links`() {
        val s = TorrentSourceClassifier.classify(" magnet:?xt=urn:btih:$hex ").getOrThrow()
        assertTrue(s is TorrentSource.Magnet)
    }

    @Test
    fun `classifies http and https torrent urls and strips fragments`() {
        val s = TorrentSourceClassifier.classify("https://example.com/release.torrent#frag").getOrThrow()
        assertEquals("https://example.com/release.torrent", (s as TorrentSource.Remote).url)
        assertTrue(TorrentSourceClassifier.classify("http://example.com/a/b.torrent").getOrThrow() is TorrentSource.Remote)
    }

    @Test
    fun `classifies safe-uri content and file locations`() {
        assertTrue(
            TorrentSourceClassifier.classify("content://com.android.providers.downloads/documents/12").getOrThrow()
                is TorrentSource.LocalFile,
        )
        assertTrue(TorrentSourceClassifier.classify("file:///sdcard/x.torrent").getOrThrow() is TorrentSource.LocalFile)
    }

    @Test
    fun `bare filename is treated as a local torrent`() {
        val s = TorrentSourceClassifier.classify("/storage/emulated/0/Download/ubuntu.torrent").getOrThrow()
        assertEquals("ubuntu.torrent", (s as TorrentSource.LocalFile).displayName)
    }

    @Test
    fun `rejects dangerous or unsupported schemes`() {
        assertEquals(TorrentInputError.UnsupportedScheme, failure("javascript:alert(1)"))
        assertEquals(TorrentInputError.UnsupportedScheme, failure("data:text/plain,hello"))
        assertEquals(TorrentInputError.UnsupportedScheme, failure("intent://evil#Intent;end"))
    }

    @Test
    fun `rejects malformed urls and unrecognized text`() {
        assertEquals(TorrentInputError.MalformedUrl, failure("https://exa mple.com/x.torrent"))
        assertEquals(TorrentInputError.MalformedUrl, failure("https:///nohost.torrent"))
        assertEquals(TorrentInputError.UnrecognizedInput, failure("just some words"))
        assertEquals(TorrentInputError.Empty, failure("   "))
    }

    @Test
    fun `propagates specific magnet errors`() {
        assertEquals(TorrentInputError.MagnetMissingInfoHash, failure("magnet:?dn=Nothing"))
    }
}
