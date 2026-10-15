package dev.torrentlens.core.domain.security

import java.security.MessageDigest

/** A hex-encoded message digest together with the algorithm that produced it. */
data class Digest(val algorithm: String, val hex: String) {
    init {
        require(hex.isNotEmpty() && hex.all { it in "0123456789abcdef" }) {
            "Digest hex must be lowercase hexadecimal"
        }
    }

    override fun toString(): String = "$algorithm:$hex"

    companion object {
        fun parse(value: String): Digest? {
            val idx = value.indexOf(':')
            if (idx <= 0 || idx == value.length - 1) return null
            val algo = value.substring(0, idx).lowercase()
            val hex = value.substring(idx + 1).lowercase()
            if (hex.isEmpty() || hex.any { it !in "0123456789abcdef" }) return null
            return Digest(algo, hex)
        }

        fun sha256Of(bytes: ByteArray): Digest = Digest("sha256", hex(MessageDigest.getInstance("SHA-256").digest(bytes)))
        fun sha512Of(bytes: ByteArray): Digest = Digest("sha512", hex(MessageDigest.getInstance("SHA-512").digest(bytes)))

        private fun hex(bytes: ByteArray): String {
            val sb = StringBuilder(bytes.size * 2)
            for (b in bytes) {
                val v = b.toInt() and 0xFF
                sb.append("0123456789abcdef"[v ushr 4])
                sb.append("0123456789abcdef"[v and 0x0F])
            }
            return sb.toString()
        }
    }
}

/**
 * Verifies downloaded content against an expected digest.
 *
 * The comparison is constant-time. For hash equality over public artifacts that
 * is not strictly required, but the same routine is reused for verifying
 * signatures and tokens, so it is written once and written safely.
 */
object IntegrityVerifier {

    fun verify(expected: Digest, actual: Digest): Boolean {
        if (!expected.algorithm.equals(actual.algorithm, ignoreCase = true)) return false
        return constantTimeEquals(expected.hex, actual.hex)
    }

    fun verify(expectedHex: String, actual: Digest): Boolean =
        constantTimeEquals(expectedHex.lowercase(), actual.hex)

    /** Streams a file so we never hold a multi-gigabyte download in memory. */
    fun hashFile(path: java.nio.file.Path, algorithm: String = "SHA-256"): Digest {
        val md = MessageDigest.getInstance(algorithm)
        java.nio.file.Files.newInputStream(path).use { input ->
            val buf = ByteArray(1 shl 16)
            while (true) {
                val read = input.read(buf)
                if (read < 0) break
                md.update(buf, 0, read)
            }
        }
        val hex = md.digest().joinToString("") { "%02x".format(it) }
        return Digest(algorithm.lowercase().replace("-", ""), hex)
    }

    internal fun constantTimeEquals(a: String, b: String): Boolean {
        val x = a.toByteArray(Charsets.UTF_8)
        val y = b.toByteArray(Charsets.UTF_8)
        // Fold length difference into the result instead of branching, so the
        // loop count does not leak the expected length.
        var diff = x.size xor y.size
        val n = maxOf(x.size, y.size)
        for (i in 0 until n) {
            val xb = if (i < x.size) x[i].toInt() else 0
            val yb = if (i < y.size) y[i].toInt() else 0
            diff = diff or (xb xor yb)
        }
        return diff == 0
    }
}
