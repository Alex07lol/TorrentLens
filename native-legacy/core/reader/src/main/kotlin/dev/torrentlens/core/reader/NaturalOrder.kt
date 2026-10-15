package dev.torrentlens.core.reader

/**
 * Splits a string into digit and non-digit runs so `page2.jpg` sorts before
 * `page10.jpg`. Comic archives are almost never zero-padded, so lexicographic
 * ordering would put page 10 before page 2.
 */
object NaturalOrder : Comparator<String> {
    override fun compare(a: String, b: String): Int {
        val ta = tokenize(a)
        val tb = tokenize(b)
        for (i in 0 until minOf(ta.size, tb.size)) {
            val x = ta[i]
            val y = tb[i]
            val cmp = if (x is Long && y is Long) {
                x.compareTo(y)
            } else {
                x.toString().compareTo(y.toString(), ignoreCase = true)
            }
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
            current.append(c)
        }
        flush()
        return out
    }

    /** Compares by the last path segment, which is what a comic page name is. */
    fun comparePaths(a: String, b: String): Int = compare(a.substringAfterLast('/'), b.substringAfterLast('/'))
}
