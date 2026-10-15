package dev.torrentlens.core.domain.torrent

import dev.torrentlens.core.domain.util.Percent

/**
 * A parsed `magnet:` URI (BEP 9 / BEP 53).
 *
 * The magnet carries *metadata about the metadata*: it is completely
 * attacker-controlled, so nothing here is trusted. Parsing is strict and total:
 * a malformed input yields a [ParseResult.Invalid] with a machine-readable
 * [MagnetError] rather than throwing, because magnet text arrives straight from
 * the clipboard.
 */
data class MagnetUri private constructor(
    val v1InfoHash: InfoHash?,
    val v2MultihashHex: String?,
    val displayName: String?,
    val trackers: List<String>,
    val exactLength: Long?,
    val webSeeds: List<String>,
    val peerAddresses: List<String>,
) {
    /** A magnet is usable only if we can derive a torrent identity from it. */
    val isUsable: Boolean get() = v1InfoHash != null || v2MultihashHex != null

    sealed interface ParseResult {
        data class Valid(val magnet: MagnetUri) : ParseResult
        data class Invalid(val error: MagnetError) : ParseResult
    }

    enum class MagnetError { NOT_A_MAGNET, MISSING_INFO_HASH, MALFORMED_INFO_HASH, UNSUPPORTED_HASH }

    companion object {
        private const val PREFIX = "magnet:?"

        /**
         * Parses a magnet URI. Never throws.
         *
         * @param maxTrackers guard against clipboard payloads padded with
         *   thousands of tracker entries (a cheap denial-of-service on the UI).
         * @param maxUriLength guard against pathological paste sizes.
         */
        fun parse(
            input: String,
            maxTrackers: Int = 64,
            maxUriLength: Int = 8192,
        ): ParseResult {
            val text = input.trim()
            if (!text.lowercase().startsWith(PREFIX)) {
                return ParseResult.Invalid(MagnetError.NOT_A_MAGNET)
            }
            if (text.length > maxUriLength) {
                return ParseResult.Invalid(MagnetError.NOT_A_MAGNET)
            }

            val query = text.substring(PREFIX.length)
            val params = query.split('&')

            var btih: String? = null
            var btmh: String? = null
            var anyXtSeen = false
            var dn: String? = null
            val trackers = mutableListOf<String>()
            val webSeeds = mutableListOf<String>()
            val peers = mutableListOf<String>()
            var xl: Long? = null

            for (param in params) {
                if (param.isEmpty()) continue
                val eq = param.indexOf('=')
                val rawKey = if (eq < 0) param else param.substring(0, eq)
                val rawValue = if (eq < 0) "" else param.substring(eq + 1)
                val key = Percent.decode(rawKey).lowercase()
                val value = Percent.decode(rawValue)

                when (key) {
                    "xt" -> {
                        anyXtSeen = true
                        val urn = value.lowercase()
                        when {
                            urn.startsWith("urn:btih:") -> btih = btih ?: value.substring(9)
                            urn.startsWith("urn:btmh:") -> btmh = btmh ?: value.substring(9)
                        }
                    }
                    "dn" -> if (dn == null) dn = value
                    "tr" -> if (trackers.size < maxTrackers && value.isNotBlank()) trackers += value
                    "ws" -> if (webSeeds.size < maxTrackers && value.isNotBlank()) webSeeds += value
                    "x.pe" -> if (peers.size < maxTrackers && value.isNotBlank()) peers += value
                    "xl" -> xl = xl ?: value.toLongOrNull()?.takeIf { it >= 0 }
                }
            }

            val v1 = btih?.let { InfoHash.parse(it) }
            if (btih != null && v1 == null) {
                return ParseResult.Invalid(MagnetError.MALFORMED_INFO_HASH)
            }

            val v2 = btmh?.let { normalizeV2(it) }
            if (v1 == null && v2 == null) {
                return ParseResult.Invalid(
                    when {
                        !anyXtSeen -> MagnetError.MISSING_INFO_HASH
                        else -> MagnetError.UNSUPPORTED_HASH
                    },
                )
            }

            return ParseResult.Valid(
                MagnetUri(
                    v1InfoHash = v1,
                    v2MultihashHex = v2,
                    displayName = dn?.takeIf { it.isNotBlank() }?.let(::sanitizeDisplayName),
                    trackers = trackers.distinct(),
                    exactLength = xl,
                    webSeeds = webSeeds.distinct(),
                    peerAddresses = peers.distinct(),
                ),
            )
        }

        /**
         * `urn:btmh:` values are multihashes, e.g. `1220<64 hex chars>` where
         * `0x12` = sha2-256 and `0x20` = 32-byte length. We record the digest
         * but do not pretend it is a v1 info-hash.
         */
        private fun normalizeV2(value: String): String? {
            val hex = value.removePrefix("0x")
            val digest = when {
                hex.length == 64 -> hex
                hex.length == 68 && hex.startsWith("1220", ignoreCase = true) -> hex.substring(4)
                else -> return null
            }
            return digest.lowercase().takeIf { d -> d.all { it in "0123456789abcdef" } }
        }

        /** Display names come from remote peers; strip control chars and clamp. */
        private fun sanitizeDisplayName(name: String): String =
            name.filter { it.code >= 0x20 && it.code != 0x7F }
                .take(255)
                .trim()
    }
}
