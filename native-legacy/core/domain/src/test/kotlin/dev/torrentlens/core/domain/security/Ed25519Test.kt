package dev.torrentlens.core.domain.security

import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.interfaces.EdECPublicKey
import java.util.Base64
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class Ed25519Test {

    private fun newKeyPair(): KeyPair = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()

    /** RFC 8032 encoding: little-endian y, top bit of the last byte = sign of x. */
    private fun rawPublicKey(pub: EdECPublicKey): ByteArray {
        val point = pub.point
        var be = point.y.toByteArray()
        if (be.size > 32) be = be.copyOfRange(be.size - 32, be.size)
        val out = ByteArray(32)
        System.arraycopy(be, 0, out, 32 - be.size, be.size)
        out.reverse()
        if (point.isXOdd) out[31] = (out[31].toInt() or 0x80).toByte()
        return out
    }

    private fun sign(kp: KeyPair, message: ByteArray): ByteArray =
        Signature.getInstance("Ed25519").run {
            initSign(kp.private)
            update(message)
            sign()
        }

    @Test
    fun `verifies a genuine signature round trip`() {
        val kp = newKeyPair()
        val message = "{\"version\":\"1.4.0\"}".toByteArray()
        val sig = sign(kp, message)
        val raw = rawPublicKey(kp.public as EdECPublicKey)
        assertEquals(32, raw.size)
        assertEquals(64, sig.size)
        assertTrue(Ed25519.verify(raw, sig, message))
    }

    @Test
    fun `rejects tampered message, wrong key and truncated signature`() {
        val kp = newKeyPair()
        val other = newKeyPair()
        val message = "manifest-body".toByteArray()
        val sig = sign(kp, message)

        assertFalse(Ed25519.verify(rawPublicKey(kp.public as EdECPublicKey), sig, "manifest-bdy".toByteArray()))
        val sig2 = sign(other, message)
        assertFalse(Ed25519.verify(rawPublicKey(kp.public as EdECPublicKey), sig2, message))
        assertFalse(Ed25519.verify(rawPublicKey(kp.public as EdECPublicKey), sig.copyOf(63), message))
        assertFalse(Ed25519.verify(ByteArray(31), sig, message))
    }

    @Test
    fun `raw key encoding is deterministic for the same key`() {
        val kp = newKeyPair()
        val pub = kp.public as EdECPublicKey
        assertArrayEquals(rawPublicKey(pub), rawPublicKey(pub))
        assertNull(Ed25519.publicKeyFromRaw(ByteArray(33)))
    }

    @Test
    fun `publisher verifier enforces a pinned key when one is provided`() {
        val kp = newKeyPair()
        val raw = rawPublicKey(kp.public as EdECPublicKey)
        val message = "body".toByteArray()
        val detached = DetachedSignature(
            algorithm = "ed25519",
            publicKey = Base64.getEncoder().encodeToString(raw),
            signature = Base64.getEncoder().encodeToString(sign(kp, message)),
        )

        assertEquals(
            SignatureVerdict.Valid,
            PublisherSignatureVerifier.verify(message, detached, trustedPublicKeys = setOf(raw.joinToString("") { "%02x".format(it) })),
        )

        // A different pinned key must block it, even though the signature itself is valid.
        val attacker = newKeyPair()
        val attackerHex = rawPublicKey(attacker.public as EdECPublicKey).joinToString("") { "%02x".format(it) }
        assertEquals(
            SignatureVerdict.Invalid(SignatureReason.NO_TRUSTED_KEY),
            PublisherSignatureVerifier.verify(message, detached, trustedPublicKeys = setOf(attackerHex)),
        )

        assertEquals(
            SignatureVerdict.Invalid(SignatureReason.UNSUPPORTED_ALGORITHM),
            PublisherSignatureVerifier.verify(message, detached.copy(algorithm = "rsa"), trustedPublicKeys = setOf()),
        )
        assertEquals(
            SignatureVerdict.Invalid(SignatureReason.SIGNATURE_MISMATCH),
            PublisherSignatureVerifier.verify("other".toByteArray(), detached, trustedPublicKeys = setOf()),
        )
        assertEquals(
            SignatureVerdict.Invalid(SignatureReason.MALFORMED_PUBLIC_KEY),
            PublisherSignatureVerifier.verify(message, detached.copy(publicKey = "!!!not-base64!!!"), trustedPublicKeys = setOf()),
        )
    }

    @Test
    fun `accepts the ed25519 prefix form for keys`() {
        val kp = newKeyPair()
        val raw = rawPublicKey(kp.public as EdECPublicKey)
        val message = "m".toByteArray()
        val detached = DetachedSignature(
            algorithm = "Ed25519",
            publicKey = "ed25519:" + Base64.getEncoder().encodeToString(raw),
            signature = Base64.getEncoder().encodeToString(sign(kp, message)),
        )
        assertEquals(SignatureVerdict.Valid, PublisherSignatureVerifier.verify(message, detached, setOf()))
    }
}
