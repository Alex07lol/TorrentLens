package dev.torrentlens.core.domain.github

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SemanticVersionTest {

    @Test
    fun `parses tolerant release tags`() {
        assertEquals("1.2.3", SemanticVersion.parse("1.2.3")!!.coreString)
        assertEquals("1.2.3", SemanticVersion.parse("v1.2.3")!!.coreString)
        assertEquals("2.0.0", SemanticVersion.parse("v2")!!.coreString)
        assertEquals("2.1.0", SemanticVersion.parse("2.1")!!.coreString)
        assertEquals("1.2.3", SemanticVersion.parse("1.2.3+build.9")!!.coreString)
        assertNull(SemanticVersion.parse("nightly"))
        assertNull(SemanticVersion.parse(""))
    }

    @Test
    fun `orders core components numerically`() {
        assertTrue(SemanticVersion.parse("1.2.3")!! < SemanticVersion.parse("1.2.4")!!)
        assertTrue(SemanticVersion.parse("1.9.0")!! < SemanticVersion.parse("1.10.0")!!)
        assertTrue(SemanticVersion.parse("2.0.0")!! > SemanticVersion.parse("1.99.99")!!)
        assertEquals(0, SemanticVersion.parse("1.0.0")!!.compareTo(SemanticVersion.parse("v1.0.0")!!))
    }

    @Test
    fun `prereleases sort below their release`() {
        assertTrue(SemanticVersion.parse("1.0.0-rc.1")!! < SemanticVersion.parse("1.0.0")!!)
        assertTrue(SemanticVersion.parse("1.0.0-rc.1")!! < SemanticVersion.parse("1.0.0-rc.2")!!)
        assertTrue(SemanticVersion.parse("1.0.0-alpha")!! < SemanticVersion.parse("1.0.0-beta")!!)
        assertTrue(SemanticVersion.parse("1.0.0-alpha")!! < SemanticVersion.parse("1.0.0-alpha.1")!!)
    }

    @Test
    fun `numeric identifiers have lower precedence than alphanumeric`() {
        assertTrue(SemanticVersion.parse("1.0.0-1")!! < SemanticVersion.parse("1.0.0-alpha")!!)
        assertTrue(SemanticVersion.parse("1.0.0-2")!! < SemanticVersion.parse("1.0.0-10")!!)
        assertEquals(0, SemanticVersion.parse("1.0.0-2")!!.compareTo(SemanticVersion.parse("1.0.0-2")!!))
    }

    @Test
    fun `build metadata does not affect precedence`() {
        assertEquals(0, SemanticVersion.parse("1.0.0+a")!!.compareTo(SemanticVersion.parse("1.0.0+b")!!))
    }

    @Test
    fun `release comparator falls back to natural ordering for non-semver tags`() {
        val cmp = ReleaseVersionComparator
        assertTrue(cmp.compare("2026.09", "2026.10") < 0)
        assertTrue(cmp.compare("r9", "r10") < 0)
        assertTrue(cmp.compare("v1.2.0", "v1.10.0") < 0)
        assertEquals(0, cmp.compare("1.0.0", "v1.0.0"))
    }
}
