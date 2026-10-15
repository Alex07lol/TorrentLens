package dev.torrentlens.core.domain.security

import java.math.BigInteger
import java.security.KeyFactory
import java.security.PublicKey
import java.security.Signature
import java.security.spec.EdECPoint
import java.security.spec.EdECPublicKeySpec
import java.security.spec.NamedParameterSpec
import java.util.Base64

/**
 * Ed25519 detached-signature verification on the plain JVM (JDK 15+), so the
 * publisher-signing rules are testable off-device and identical on Android.
 *
 * Android API 28+ ships the same `java.security` providers, so no BouncyCastle
 * dependency is required for the default path; it is only pulled in as a
 * fallback for provider-less environments.
 */
object Ed25519 {
    const val ALGORITHM = "Ed25519"
    const val PUBLIC_KEY_BYTES = 32
    const val SIGNATURE_BYTES = 64

    /**
     * Builds a [PublicKey] from the 32-byte RFC 8032 encoding.
     *
     * The encoding is the little-endian integer y, with the most significant bit
     * of the last byte holding the sign of x.
     */
    fun publicKeyFromRaw(raw: ByteArray): PublicKey? {
        if (raw.size != PUBLIC_KEY_BYTES) return null
        val yBytes = raw.copyOf()
        val last = yBytes[PUBLIC_KEY_BYTES - 1].toInt() and 0xFF
        val xOdd = (last and 0x80) != 0
        yBytes[PUBLIC_KEY_BYTES - 1] = (last and 0x7F).toByte()
        val y = BigInteger(1, yBytes.reversedArray())
        return runCatching {
            KeyFactory.getInstance(ALGORITHM)
                .generatePublic(EdECPublicKeySpec(NamedParameterSpec.ED25519, EdECPoint(xOdd, y)))
        }.getOrNull()
    }

    fun verify(publicKeyRaw: ByteArray, signature: ByteArray, message: ByteArray): Boolean {
        if (signature.size != SIGNATURE_BYTES) return false
        val key = publicKeyFromRaw(publicKeyRaw) ?: return false
        return runCatching {
            Signature.getInstance(ALGORITHM).run {
                initVerify(key)
                update(message)
                verify(signature)
            }
        }.getOrDefault(false)
    }

    fun decodeBase64(value: String): ByteArray? =
        runCatching { Base64.getDecoder().decode(value.trim()) }.getOrNull()
}
