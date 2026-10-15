package dev.torrentlens.core.domain.github

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GitHubRefTest {

    private fun valid(input: String): GitHubRefParseResult.Valid {
        val r = GitHubRef.parse(input)
        assertTrue("expected valid for: $input", r is GitHubRefParseResult.Valid)
        return r as GitHubRefParseResult.Valid
    }

    private fun error(input: String): GitHubRefError {
        val r = GitHubRef.parse(input)
        assertTrue("expected invalid for: $input", r is GitHubRefParseResult.Invalid)
        return (r as GitHubRefParseResult.Invalid).error
    }

    @Test
    fun `parses every accepted url shape`() {
        assertEquals("owner/repo", valid("owner/repo").ref.slug)
        assertEquals("owner/repo", valid("https://github.com/owner/repo").ref.slug)
        assertEquals("owner/repo", valid("https://github.com/owner/repo/").ref.slug)
        assertEquals("owner/repo", valid("github.com/owner/repo").ref.slug)
        assertEquals("owner/repo", valid("git@github.com:owner/repo.git").ref.slug)
        assertEquals("owner/repo", valid("https://github.com/owner/repo/releases").ref.slug)
        assertEquals("owner/repo", valid("https://github.com/owner/repo/releases/latest").ref.slug)
    }

    @Test
    fun `extracts a release tag when present`() {
        assertEquals("v1.2.3", valid("https://github.com/owner/repo/releases/tag/v1.2.3").releaseTag)
        assertNull(valid("https://github.com/owner/repo/releases").releaseTag)
    }

    @Test
    fun `rejects non-github, reserved and malformed owners`() {
        assertEquals(GitHubRefError.NotGitHub, error("https://gitlab.com/owner/repo"))
        assertEquals(GitHubRefError.NotGitHub, error("git@gitlab.com:owner/repo.git"))
        assertEquals(GitHubRefError.Empty, error("   "))
        assertEquals(GitHubRefError.MissingRepository, error("https://github.com/owner"))
        assertEquals(GitHubRefError.InvalidOwner, error("https://github.com/orgs/foo"))
        assertEquals(GitHubRefError.InvalidOwner, error("https://github.com/settings/profile"))
        assertEquals(GitHubRefError.InvalidOwner, error("https://github.com/bad..name/repo"))
    }

    @Test
    fun `api url is built from validated parts and clamps paging`() {
        val ref = GitHubRef.of("owner", "repo")!!
        assertEquals(
            "https://api.github.com/repos/owner/repo/releases?per_page=30&page=1",
            ref.releasesApiUrl(),
        )
        assertEquals(
            "https://api.github.com/repos/owner/repo/releases?per_page=100&page=2",
            ref.releasesApiUrl(perPage = 5000, page = 2),
        )
        assertEquals(
            "https://api.github.com/repos/owner/repo/releases?per_page=1&page=1",
            ref.releasesApiUrl(perPage = 0, page = -3),
        )
    }

    @Test
    fun `of validates directly`() {
        assertNull(GitHubRef.of("bad owner", "repo"))
        assertNull(GitHubRef.of("owner", ".."))
        assertEquals("owner/repo", GitHubRef.of("@owner", "repo.git")!!.slug)
    }
}
