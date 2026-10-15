package dev.torrentlens.core.domain.security

import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class IntegrityTest {

    @Test
    fun `sha256 matches published NIST vectors`() {
        assertEquals(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            Digest.sha256Of(ByteArray(0)).hex,
        )
        assertEquals(
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            Digest.sha256Of("abc".toByteArray()).hex,
        )
    }

    @Test
    fun `verify compares digests of the same algorithm`() {
        val a = Digest.sha256Of("payload".toByteArray())
        val b = Digest.sha256Of("payload".toByteArray())
        val c = Digest.sha256Of("payload!".toByteArray())
        assertTrue(IntegrityVerifier.verify(a, b))
        assertFalse(IntegrityVerifier.verify(a, c))
        assertFalse(IntegrityVerifier.verify(Digest.sha512Of("payload".toByteArray()), a))
    }

    @Test
    fun `hashFile streams the same digest as in-memory hashing`() {
        val bytes = ByteArray(300_000) { (it % 251).toByte() }
        val file = Files.createTempFile("tl-hash", ".bin")
        Files.write(file, bytes)
        assertEquals(Digest.sha256Of(bytes), IntegrityVerifier.hashFile(file))
    }

    @Test
    fun `digest parsing is strict`() {
        assertEquals(Digest("sha256", "ab"), Digest.parse("SHA256:AB"))
        assertNull(Digest.parse("sha256"))
        assertNull(Digest.parse("sha256:zz"))
        assertNull(Digest.parse(":ab"))
    }

    @Test
    fun `constant time equality handles differing lengths`() {
        assertTrue(IntegrityVerifier.constantTimeEquals("abcd", "abcd"))
        assertFalse(IntegrityVerifier.constantTimeEquals("abcd", "abcde"))
        assertFalse(IntegrityVerifier.constantTimeEquals("", "a"))
    }
}
