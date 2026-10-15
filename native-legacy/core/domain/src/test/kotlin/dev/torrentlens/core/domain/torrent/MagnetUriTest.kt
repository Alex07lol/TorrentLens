package dev.torrentlens.core.domain.torrent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MagnetUriTest {

    private val hex = "0123456789abcdef0123456789abcdef01234567"

    private fun valid(input: String): MagnetUri {
        val r = MagnetUri.parse(input)
        assertTrue("expected valid: $input", r is MagnetUri.ParseResult.Valid)
        return (r as MagnetUri.ParseResult.Valid).magnet
    }

    private fun invalid(input: String): MagnetUri.MagnetError {
        val r = MagnetUri.parse(input)
        assertTrue("expected invalid: $input", r is MagnetUri.ParseResult.Invalid)
        return (r as MagnetUri.ParseResult.Invalid).error
    }

    @Test
    fun `parses hash, display name and trackers`() {
        val m = valid(
            "magnet:?xt=urn:btih:$hex&dn=Debian%20ISO&tr=udp%3A%2F%2Ftracker.example%3A80%2Fannounce" +
                "&tr=udp://second.example:6969&xl=12345&ws=https://mirror.example/file.iso",
        )
        assertEquals(hex, m.v1InfoHash!!.hex)
        assertEquals("Debian ISO", m.displayName)
        assertEquals(2, m.trackers.size)
        assertEquals("udp://tracker.example:80/announce", m.trackers[0])
        assertEquals(12345L, m.exactLength)
        assertEquals(1, m.webSeeds.size)
        assertTrue(m.isUsable)
    }

    @Test
    fun `accepts base32 v1 hash`() {
        val base32 = InfoHash.fromHex(hex)!!.base32
        val m = valid("magnet:?xt=urn:btih:$base32")
        assertEquals(hex, m.v1InfoHash!!.hex)
    }

    @Test
    fun `records bittorrent v2 multihash separately from v1`() {
        val digest = "ab".repeat(32)
        val m = valid("magnet:?xt=urn:btmh:1220$digest")
        assertEquals(digest, m.v2MultihashHex)
        assertEquals(null, m.v1InfoHash)
        assertTrue(m.isUsable)
    }

    @Test
    fun `report distinct errors`() {
        assertEquals(MagnetUri.MagnetError.NOT_A_MAGNET, invalid("https://example.com"))
        assertEquals(MagnetUri.MagnetError.MISSING_INFO_HASH, invalid("magnet:?dn=NoHash"))
        assertEquals(MagnetUri.MagnetError.MALFORMED_INFO_HASH, invalid("magnet:?xt=urn:btih:tooshort"))
        assertEquals(MagnetUri.MagnetError.UNSUPPORTED_HASH, invalid("magnet:?xt=urn:sha256:${"0".repeat(64)}"))
    }

    @Test
    fun `percent decoding is strict about plus`() {
        // '+' must survive as a literal, unlike application/x-www-form-urlencoded.
        val m = valid("magnet:?xt=urn:btih:$hex&dn=C%2B%2B%20Guide")
        assertEquals("C++ Guide", m.displayName)
    }

    @Test
    fun `truncated percent escape does not drop data`() {
        val m = valid("magnet:?xt=urn:btih:$hex&dn=100%")
        assertEquals("100%", m.displayName)
    }

    @Test
    fun `display name strips control characters and clamps length`() {
        val m = valid("magnet:?xt=urn:btih:$hex&dn=" + "a".repeat(400) + "%00%07")
        assertEquals(255, m.displayName!!.length)
        assertFalse(m.displayName!!.any { it.code < 0x20 })
    }

    @Test
    fun `tracker list is bounded`() {
        // 200 realistic trackers stays under the URI length guard, but well
        // above the 64-tracker cap we enforce against clipboard padding.
        val trackers = (1..200).joinToString("&") { "tr=udp://t$it.x:80" }
        val m = valid("magnet:?xt=urn:btih:$hex&$trackers")
        assertEquals(64, m.trackers.size)
    }

    @Test
    fun `over-long input is rejected rather than parsed`() {
        val huge = "magnet:?xt=urn:btih:$hex&dn=" + "x".repeat(20000)
        assertEquals(MagnetUri.MagnetError.NOT_A_MAGNET, invalid(huge))
    }
}
