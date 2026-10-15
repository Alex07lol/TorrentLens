package dev.torrentlens.core.domain.torrent

/**
 * A BitTorrent v1 info-hash (BEP 3 / BEP 9): 20 raw SHA-1 bytes, rendered as
 * either 40 lowercase hex characters or 32 uppercase base32 characters.
 *
 * v2 (BEP 52) multihashes are tracked separately in [MagnetUri] because they are
 * a different length and must not be silently coerced into a v1 hash.
 */
class InfoHash private constructor(private val raw: ByteArray) {

    val hex: String = raw.joinToString("") { "%02x".format(it) }

    val base32: String = Base32.encodeUpper(raw)

    /** Defensive copy — callers must not be able to mutate the identity of a hash. */
    fun bytes(): ByteArray = raw.copyOf()

    override fun equals(other: Any?): Boolean =
        this === other || (other is InfoHash && raw.contentEquals(other.raw))

    override fun hashCode(): Int = raw.contentHashCode()

    override fun toString(): String = hex

    companion object {
        const val LENGTH_BYTES = 20

        /** Accepts 40-char hex (either case) or 32-char base32 (either case). */
        fun parse(value: String): InfoHash? {
            val trimmed = value.trim()
            return when (trimmed.length) {
                40 -> fromHex(trimmed)
                32 -> fromBase32(trimmed)
                else -> null
            }
        }

        fun fromHex(value: String): InfoHash? {
            if (value.length != 40) return null
            val out = ByteArray(LENGTH_BYTES)
            for (i in 0 until LENGTH_BYTES) {
                val hi = Character.digit(value[i * 2], 16)
                val lo = Character.digit(value[i * 2 + 1], 16)
                if (hi < 0 || lo < 0) return null
                out[i] = ((hi shl 4) or lo).toByte()
            }
            return InfoHash(out)
        }

        fun fromBase32(value: String): InfoHash? =
            Base32.decodeUpper(value)?.takeIf { it.size == LENGTH_BYTES }?.let(::InfoHash)

        fun of(raw: ByteArray): InfoHash {
            require(raw.size == LENGTH_BYTES) {
                "BitTorrent v1 info-hash must be $LENGTH_BYTES bytes, got ${raw.size}"
            }
            return InfoHash(raw.copyOf())
        }
    }
}

/** RFC 4648 base32 without padding, as used by the `urn:btih:` base32 form. */
internal object Base32 {
    private const val ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    fun encodeUpper(data: ByteArray): String {
        val sb = StringBuilder((data.size * 8 + 4) / 5)
        var buffer = 0
        var bits = 0
        for (b in data) {
            buffer = (buffer shl 8) or (b.toInt() and 0xFF)
            bits += 8
            while (bits >= 5) {
                sb.append(ALPHABET[(buffer shr (bits - 5)) and 0x1F])
                bits -= 5
            }
        }
        if (bits > 0) sb.append(ALPHABET[(buffer shl (5 - bits)) and 0x1F])
        return sb.toString()
    }

    fun decodeUpper(value: String): ByteArray? {
        val out = java.io.ByteArrayOutputStream()
        var buffer = 0
        var bits = 0
        for (c in value) {
            val idx = ALPHABET.indexOf(c.uppercaseChar())
            if (idx < 0) return null
            buffer = (buffer shl 5) or idx
            bits += 5
            if (bits >= 8) {
                out.write((buffer shr (bits - 8)) and 0xFF)
                bits -= 8
            }
        }
        return out.toByteArray()
    }
}
