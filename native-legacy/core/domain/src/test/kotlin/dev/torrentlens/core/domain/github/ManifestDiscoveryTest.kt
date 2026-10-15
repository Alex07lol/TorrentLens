package dev.torrentlens.core.domain.github

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ManifestDiscoveryTest {

    @Test
    fun `prefers canonical names in order`() {
        val r = ManifestDiscovery.discover(listOf("app.apk", "update-manifest.json", "manifest.json"))
        assertEquals(ManifestDiscovery.Result.Found("update-manifest.json", ManifestDiscovery.Tier.CANONICAL), r)
    }

    @Test
    fun `matches canonical names case-insensitively and ignores directories`() {
        val r = ManifestDiscovery.discover(listOf("assets/TorrentLens-Manifest.json"))
        assertEquals(ManifestDiscovery.Result.Found("TorrentLens-Manifest.json", ManifestDiscovery.Tier.CANONICAL), r)
    }

    @Test
    fun `falls back to a unique convention match`() {
        val r = ManifestDiscovery.discover(listOf("notes.txt", "release-42.manifest.json"))
        assertEquals(ManifestDiscovery.Result.Found("release-42.manifest.json", ManifestDiscovery.Tier.CONVENTION), r)
    }

    @Test
    fun `refuses to guess between several convention matches`() {
        val r = ManifestDiscovery.discover(listOf("a.manifest.json", "b.manifest.json"))
        assertTrue(r is ManifestDiscovery.Result.Ambiguous)
        assertEquals(listOf("a.manifest.json", "b.manifest.json"), (r as ManifestDiscovery.Result.Ambiguous).candidates)
    }

    @Test
    fun `reports nothing found`() {
        assertEquals(ManifestDiscovery.Result.NotFound, ManifestDiscovery.discover(emptyList()))
        assertEquals(ManifestDiscovery.Result.NotFound, ManifestDiscovery.discover(listOf("app.apk", "README.md")))
    }
}
