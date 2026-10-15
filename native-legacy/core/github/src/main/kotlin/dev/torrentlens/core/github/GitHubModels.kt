package dev.torrentlens.core.github

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Release/asset shapes returned by the GitHub REST API. Only the fields we
 * actually use are declared; `ignoreUnknownKeys` lets GitHub add fields without
 * breaking us.
 */
@Serializable
data class GitHubAsset(
    val id: Long,
    val name: String,
    @SerialName("browser_download_url") val downloadUrl: String,
    val size: Long = 0,
    @SerialName("content_type") val contentType: String? = null,
)

@Serializable
data class GitHubRelease(
    val id: Long,
    @SerialName("tag_name") val tagName: String,
    val name: String? = null,
    val draft: Boolean = false,
    val prerelease: Boolean = false,
    @SerialName("published_at") val publishedAt: String? = null,
    @SerialName("html_url") val htmlUrl: String? = null,
    val body: String? = null,
    val assets: List<GitHubAsset> = emptyList(),
)

/** Honest snapshot of the API's rate-limit state for graceful UI handling. */
data class RateLimit(
    val remaining: Int?,
    val limit: Int?,
    /** Epoch seconds at which the window resets. */
    val resetAtEpochSeconds: Long?,
    val retryAfterSeconds: Long?,
) {
    val isExhausted: Boolean get() = remaining != null && remaining <= 0
}
