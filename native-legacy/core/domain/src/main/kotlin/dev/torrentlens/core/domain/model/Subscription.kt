package dev.torrentlens.core.domain.model

import dev.torrentlens.core.domain.github.GitHubRef

/** A GitHub repository/release feed the user follows. */
data class GitHubSubscription(
    val id: String,
    val owner: String,
    val repo: String,
    val displayName: String,
    val includePrereleases: Boolean = false,
    /** Minutes between scheduled checks; 0 disables automatic checks. */
    val checkIntervalMinutes: Int = 1440,
    val autoDownload: Boolean = false,
    val lastCheckedAtEpochMillis: Long? = null,
    val lastError: String? = null,
    val installedVersion: String? = null,
) {
    val ref: GitHubRef? get() = GitHubRef.of(owner, repo)
}

/** One observed release, kept for history and rollback-friendly browsing. */
data class ReleaseRecord(
    val id: String,
    val subscriptionId: String,
    val tag: String,
    val name: String?,
    val publishedAtEpochMillis: Long,
    val prerelease: Boolean,
    val manifestVersion: String?,
    /** "verified" | "unsigned" | "invalid" — never claim more than we checked. */
    val verification: String,
    val notes: String? = null,
    val downloadUrl: String? = null,
    val isInstalled: Boolean = false,
)
