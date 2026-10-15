package dev.torrentlens.core.domain.github

/**
 * A specific GitHub repository. Owner and name are validated against GitHub's
 * own naming rules so we never build a request URL out of unvalidated input
 * (which would otherwise allow path/query injection into the API call).
 */
data class GitHubRef(val owner: String, val repo: String) {

    val slug: String get() = "$owner/$repo"

    /** Canonical HTTPS URL, built from validated components only. */
    val canonicalUrl: String get() = "https://github.com/$owner/$repo"

    fun releasesApiUrl(perPage: Int = 30, page: Int = 1): String {
        val clamped = perPage.coerceIn(1, 100)
        val safePage = page.coerceAtLeast(1)
        return "https://api.github.com/repos/$owner/$repo/releases?per_page=$clamped&page=$safePage"
    }

    companion object {
        private val OWNER = Regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$")
        private val REPO = Regex("^[A-Za-z0-9._-]{1,100}$")

        /** Reserved GitHub path segments that must never be read as an owner. */
        private val RESERVED = setOf(
            "orgs", "users", "topics", "collections", "sponsors", "marketplace",
            "settings", "features", "about", "pricing", "enterprise", "login",
        )

        /** Null when the owner is acceptable; otherwise which rule it broke. */
        fun ownerError(rawOwner: String): GitHubRefError? {
            val o = rawOwner.trim().removePrefix("@")
            if (o.isEmpty()) return GitHubRefError.Empty
            if (!OWNER.matches(o)) return GitHubRefError.InvalidOwner
            if (o.lowercase() in RESERVED) return GitHubRefError.InvalidOwner
            return null
        }

        /** Null when the repository name is acceptable; otherwise which rule it broke. */
        fun repositoryError(rawRepo: String): GitHubRefError? {
            val r = rawRepo.trim().removeSuffix(".git")
            if (r.isEmpty()) return GitHubRefError.MissingRepository
            if (!REPO.matches(r) || r == "." || r == ".." || r.endsWith(".")) {
                return GitHubRefError.InvalidRepository
            }
            return null
        }

        fun of(owner: String, repo: String): GitHubRef? {
            if (ownerError(owner) != null) return null
            if (repositoryError(repo) != null) return null
            return GitHubRef(owner.trim().removePrefix("@"), repo.trim().removeSuffix(".git"))
        }

        /**
         * Parses the URL and shorthand forms a user is likely to paste.
         * Also returns the release tag if the URL pointed at a specific release.
         */
        fun parse(input: String): GitHubRefParseResult {
            val text = input.trim().removeSuffix("/")
            if (text.isEmpty()) return GitHubRefParseResult.Invalid(GitHubRefError.Empty)

            val path: String = when {
                text.startsWith("git@github.com:", ignoreCase = true) ->
                    text.substringAfter(':')

                text.startsWith("https://github.com/", true) ||
                    text.startsWith("http://github.com/", true) ->
                    text.substringAfter("github.com/")

                text.startsWith("github.com/", true) -> text.substringAfter("github.com/")

                text.contains("://") -> return GitHubRefParseResult.Invalid(GitHubRefError.NotGitHub)

                text.startsWith("git@") -> return GitHubRefParseResult.Invalid(GitHubRefError.NotGitHub)

                else -> text // bare `owner/repo` shorthand
            }

            val segments = path.removeSuffix(".git").split('/').filter { it.isNotEmpty() }
            if (segments.isEmpty()) return GitHubRefParseResult.Invalid(GitHubRefError.Empty)

            val owner = segments[0]
            var repo = ""
            var tag: String? = null

            if (segments.size == 1) {
                return GitHubRefParseResult.Invalid(GitHubRefError.MissingRepository)
            }

            repo = segments[1]
            if (segments.size >= 4 && segments[2].equals("releases", true) && segments[3].equals("tag", true)) {
                tag = segments.getOrNull(4)?.takeIf { it.isNotBlank() }
            }

            val error = ownerError(owner) ?: repositoryError(repo)
            if (error != null) return GitHubRefParseResult.Invalid(error)
            return GitHubRefParseResult.Valid(GitHubRef.of(owner, repo)!!, tag)
        }
    }
}

sealed interface GitHubRefParseResult {
    data class Valid(val ref: GitHubRef, val releaseTag: String?) : GitHubRefParseResult
    data class Invalid(val error: GitHubRefError) : GitHubRefParseResult
}

/**
 * Why a repository reference could not be parsed. A plain enum (not an
 * Exception) so callers can branch on it exhaustively; [GitHubRefException] is
 * the throwable form used with `Result.failure`.
 */
enum class GitHubRefError(val message: String) {
    Empty("Enter a GitHub repository, for example owner/repo."),
    NotGitHub("Only github.com repositories are supported."),
    MissingRepository("That URL is missing the repository name."),
    InvalidOwner("That GitHub owner name is not valid."),
    InvalidRepository("That GitHub repository name is not valid."),
}

class GitHubRefException(val error: GitHubRefError) : Exception(error.message)
