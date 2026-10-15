package dev.torrentlens.core.domain.torrent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class InfoHashTest {

    private val hex = "0123456789abcdef0123456789abcdef01234567"

    @Test
    fun `hex round-trips`() {
        val hash = InfoHash.fromHex(hex)!!
        assertEquals(hex, hash.hex)
        assertEquals(20, hash.bytes().size)
    }

    @Test
    fun `base32 round-trips against hex`() {
        val fromHex = InfoHash.fromHex(hex)!!
        val fromBase32 = InfoHash.parse(fromHex.base32)!!
        assertEquals(fromHex, fromBase32)
        assertEquals(32, fromHex.base32.length)
    }

    @Test
    fun `parse accepts both forms case-insensitively`() {
        assertEquals(InfoHash.fromHex(hex), InfoHash.parse(hex.uppercase()))
        assertEquals(InfoHash.fromHex(hex), InfoHash.parse(InfoHash.fromHex(hex)!!.base32.lowercase()))
    }

    @Test
    fun `rejects wrong lengths and non-hex`() {
        assertNull(InfoHash.fromHex(hex.dropLast(1)))
        assertNull(InfoHash.fromHex(hex + "0"))
        assertNull(InfoHash.fromHex("zz23456789abcdef0123456789abcdef01234567"))
        assertNull(InfoHash.parse("not-a-hash"))
    }

    @Test
    fun `bytes are defensively copied and identity is value-based`() {
        val a = InfoHash.fromHex(hex)!!
        val leaked = a.bytes()
        leaked[0] = 0x7F
        assertEquals(hex, a.hex)

        val b = InfoHash.fromHex(hex)!!
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
        assertNotEquals(a, InfoHash.fromHex(hex.replaceFirst('0', '1'))!!)
    }

    @Test
    fun `of enforces v1 length`() {
        assertThrows(IllegalArgumentException::class.java) { InfoHash.of(ByteArray(19)) }
    }

    @Test
    fun `base32 encoding matches RFC 4648 vectors`() {
        // RFC 4648 section 10 test vectors, unpadded.
        assertEquals("MY", Base32.encodeUpper("f".toByteArray()))
        assertEquals("MZXQ", Base32.encodeUpper("fo".toByteArray()))
        assertEquals("MZXW6", Base32.encodeUpper("foo".toByteArray()))
        assertEquals("MZXW6YQ", Base32.encodeUpper("foob".toByteArray()))
        assertEquals("MZXW6YTB", Base32.encodeUpper("fooba".toByteArray()))
        assertEquals("MZXW6YTBOI", Base32.encodeUpper("foobar".toByteArray()))
        // And the decoder inverts it.
        assertEquals("foobar", String(Base32.decodeUpper("MZXW6YTBOI")!!))
    }
}
