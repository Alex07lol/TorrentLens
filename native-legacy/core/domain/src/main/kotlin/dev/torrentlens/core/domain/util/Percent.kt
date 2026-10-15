package dev.torrentlens.core.domain.util

/**
 * Strict RFC 3986 percent-decoding.
 *
 * We deliberately do NOT use [java.net.URLDecoder]: it implements
 * `application/x-www-form-urlencoded`, which turns `+` into a space. In a magnet
 * URI a literal `+` is legal data (e.g. base32 is not used, but display names
 * and tracker URLs may contain it), so decoding it as a space would corrupt
 * otherwise valid input.
 */
internal object Percent {
    fun decode(input: String): String {
        if (input.indexOf('%') < 0) return input
        val out = StringBuilder(input.length)
        var i = 0
        while (i < input.length) {
            val c = input[i]
            if (c == '%') {
                if (i + 2 >= input.length) {
                    // Truncated escape: keep the literal character rather than
                    // silently dropping user data.
                    out.append(c); i++
                    continue
                }
                val hi = Character.digit(input[i + 1], 16)
                val lo = Character.digit(input[i + 2], 16)
                if (hi < 0 || lo < 0) {
                    out.append(c); i++
                    continue
                }
                out.append(((hi shl 4) or lo).toChar())
                i += 3
            } else {
                out.append(c); i++
            }
        }
        return out.toString()
    }
}
