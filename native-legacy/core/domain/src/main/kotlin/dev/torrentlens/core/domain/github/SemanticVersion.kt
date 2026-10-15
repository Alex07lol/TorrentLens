package dev.torrentlens.core.domain.github

/**
 * Semantic Versioning 2.0.0 with tolerance for real release tags.
 *
 * Handles a leading `v`, missing minor/patch components (`v2`, `2.1`), and
 * build metadata (ignored for precedence, per the spec). Prerelease versions
 * sort *below* the corresponding release: `1.0.0-rc.1 < 1.0.0`.
 */
data class SemanticVersion(
    val major: Int,
    val minor: Int,
    val patch: Int,
    val prerelease: List<String> = emptyList(),
    val original: String,
) : Comparable<SemanticVersion> {

    val isPrerelease: Boolean get() = prerelease.isNotEmpty()

    /** `major.minor.patch`, without any prerelease/build suffix. */
    val coreString: String get() = "$major.$minor.$patch"

    override fun compareTo(other: SemanticVersion): Int {
        major.compareTo(other.major).let { if (it != 0) return it }
        minor.compareTo(other.minor).let { if (it != 0) return it }
        patch.compareTo(other.patch).let { if (it != 0) return it }
        return comparePrerelease(prerelease, other.prerelease)
    }

    override fun toString(): String = original

    private fun comparePrerelease(a: List<String>, b: List<String>): Int {
        if (a.isEmpty() && b.isEmpty()) return 0
        if (a.isEmpty()) return 1   // release > prerelease
        if (b.isEmpty()) return -1
        val n = minOf(a.size, b.size)
        for (i in 0 until n) {
            val x = a[i]
            val y = b[i]
            val xn = x.toIntOrNull()
            val yn = y.toIntOrNull()
            val cmp = when {
                xn != null && yn != null -> xn.compareTo(yn)
                xn != null -> -1            // numeric identifiers have lower precedence
                yn != null -> 1
                else -> x.compareTo(y)
            }
            if (cmp != 0) return cmp
        }
        return a.size.compareTo(b.size)
    }

    companion object {
        private val PATTERN = Regex(
            "^v?(\\d{1,9})(?:\\.(\\d{1,9}))?(?:\\.(\\d{1,9}))?" +
                "(?:-([0-9A-Za-z.-]+))?" +
                "(?:\\+([0-9A-Za-z.-]+))?$",
        )

        fun parse(raw: String): SemanticVersion? {
            val text = raw.trim()
            if (text.isEmpty()) return null
            val m = PATTERN.matchEntire(text) ?: return null
            val major = m.groupValues[1].toIntOrNull() ?: return null
            val minor = m.groupValues[2].ifEmpty { "0" }.toIntOrNull() ?: return null
            val patch = m.groupValues[3].ifEmpty { "0" }.toIntOrNull() ?: return null
            val pre = m.groupValues[4]
                .takeIf { it.isNotEmpty() }
                ?.split('.')
                ?.filter { it.isNotEmpty() }
                ?: emptyList()
            return SemanticVersion(major, minor, patch, pre, text)
        }
    }
}

/**
 * Compares two release identifiers that may not be strict semver (some projects
 * tag releases `2026.09` or `r12`). Ordering falls back to a natural-ish
 * comparison of numeric runs so version history still sorts sensibly.
 */
object ReleaseVersionComparator : Comparator<String> {
    override fun compare(a: String, b: String): Int {
        val sa = SemanticVersion.parse(a)
        val sb = SemanticVersion.parse(b)
        if (sa != null && sb != null) return sa.compareTo(sb)
        return naturalCompare(a, b)
    }

    private fun naturalCompare(a: String, b: String): Int {
        val ta = tokenize(a)
        val tb = tokenize(b)
        val n = minOf(ta.size, tb.size)
        for (i in 0 until n) {
            val x = ta[i]
            val y = tb[i]
            val cmp = if (x is Long && y is Long) x.compareTo(y) else x.toString().compareTo(y.toString())
            if (cmp != 0) return cmp
        }
        return ta.size.compareTo(tb.size)
    }

    private fun tokenize(value: String): List<Comparable<*>> {
        val out = mutableListOf<Comparable<*>>()
        val current = StringBuilder()
        var numeric = false
        fun flush() {
            if (current.isEmpty()) return
            out += if (numeric) current.toString().toLongOrNull() ?: 0L else current.toString()
            current.clear()
        }
        for (c in value) {
            val isDigit = c.isDigit()
            if (current.isNotEmpty() && isDigit != numeric) flush()
            numeric = isDigit
            current.append(c.lowercaseChar())
        }
        flush()
        return out
    }
}
