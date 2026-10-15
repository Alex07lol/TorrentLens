package dev.torrentlens.core.github

import dev.torrentlens.core.domain.github.GitHubRef
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request

/** Why a GitHub call failed, in terms the UI can act on. */
sealed interface GitHubError {
    data class RateLimited(val rateLimit: RateLimit) : GitHubError
    data class Http(val code: Int, val body: String?) : GitHubError
    data class Network(val message: String) : GitHubError
    data class Malformed(val message: String) : GitHubError
}

sealed interface GitHubResult<out T> {
    data class Ok<T>(val value: T, val rateLimit: RateLimit) : GitHubResult<T>
    data class Err(val error: GitHubError) : GitHubResult<Nothing>
}

/**
 * Read-only GitHub REST client.
 *
 * Notes that matter:
 * - We never send a token by default; unauthenticated requests are rate limited,
 *   so every response carries the limit state back to the caller.
 * - `X-RateLimit-Remaining` / `Reset` / `Retry-After` are parsed so the
 *   subscription layer can back off instead of hammering the API.
 * - Responses are parsed leniently (`ignoreUnknownKeys`) but strictly typed:
 *   an unexpected shape is an error, not a silent partial object.
 */
class GitHubReleaseClient(
    private val client: OkHttpClient = defaultClient(),
    private val json: Json = Json { ignoreUnknownKeys = true; explicitNulls = false },
    private val userAgent: String = "TorrentLens/1.0 (+https://example.invalid/torrentlens)",
) {

    suspend fun listReleases(
        ref: GitHubRef,
        perPage: Int = 30,
        page: Int = 1,
        includePrereleases: Boolean = false,
    ): GitHubResult<List<GitHubRelease>> = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url(ref.releasesApiUrl(perPage = perPage, page = page))
            .header("Accept", "application/vnd.github+json")
            .header("X-GitHub-Api-Version", "2022-11-28")
            .header("User-Agent", userAgent)
            .get()
            .build()

        execute(request) { body ->
            val releases = json.decodeFromString<List<GitHubRelease>>(body)
            // Drafts are never published; prereleases are opt-in per subscription.
            releases.filter { !it.draft && (includePrereleases || !it.prerelease) }
        }
    }

    /** Downloads a release asset with a hard size ceiling. */
    suspend fun downloadAsset(
        url: String,
        maxBytes: Long = DEFAULT_MAX_ASSET_BYTES,
    ): GitHubResult<ByteArray> = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url(url)
            .header("Accept", "application/octet-stream")
            .header("User-Agent", userAgent)
            .get()
            .build()

        try {
            client.newCall(request).execute().use { response ->
                val rateLimit = parseRateLimit(response)
                if (!response.isSuccessful) {
                    return@use GitHubResult.Err(
                        GitHubError.Http(response.code, response.body?.string()?.take(512)),
                    )
                }
                val declared = response.header("Content-Length")?.toLongOrNull()
                if (declared != null && declared > maxBytes) {
                    return@use GitHubResult.Err(
                        GitHubError.Malformed("Asset is larger than the ${maxBytes / 1024 / 1024} MiB limit"),
                    )
                }
                val bytes = response.body?.bytes()
                    ?: return@use GitHubResult.Err(GitHubError.Malformed("Empty response body"))
                if (bytes.size > maxBytes) {
                    return@use GitHubResult.Err(GitHubError.Malformed("Asset exceeded the size limit"))
                }
                GitHubResult.Ok(bytes, rateLimit)
            }
        } catch (e: IOException) {
            GitHubResult.Err(GitHubError.Network(e.message ?: "Network error"))
        }
    }

    private inline fun <T> execute(
        request: Request,
        parse: (String) -> T,
    ): GitHubResult<T> = try {
        client.newCall(request).execute().use { response ->
            val rateLimit = parseRateLimit(response)
            val body = response.body?.string()
            when {
                response.code == 403 || response.code == 429 -> if (rateLimit.isExhausted || rateLimit.retryAfterSeconds != null) {
                    GitHubResult.Err(GitHubError.RateLimited(rateLimit))
                } else {
                    GitHubResult.Err(GitHubError.Http(response.code, body?.take(512)))
                }

                !response.isSuccessful -> GitHubResult.Err(GitHubError.Http(response.code, body?.take(512)))
                body == null -> GitHubResult.Err(GitHubError.Malformed("Empty response body"))
                else -> GitHubResult.Ok(parse(body), rateLimit)
            }
        }
    } catch (e: IOException) {
        GitHubResult.Err(GitHubError.Network(e.message ?: "Network error"))
    } catch (e: kotlinx.serialization.SerializationException) {
        GitHubResult.Err(GitHubError.Malformed(e.message ?: "Unexpected GitHub response"))
    }

    private fun parseRateLimit(response: okhttp3.Response): RateLimit = RateLimit(
        remaining = response.header("X-RateLimit-Remaining")?.toIntOrNull(),
        limit = response.header("X-RateLimit-Limit")?.toIntOrNull(),
        resetAtEpochSeconds = response.header("X-RateLimit-Reset")?.toLongOrNull(),
        retryAfterSeconds = response.header("Retry-After")?.toLongOrNull(),
    )

    companion object {
        /** Manifests are small; anything larger is not a manifest. */
        const val DEFAULT_MAX_ASSET_BYTES = 8L * 1024 * 1024

        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .callTimeout(45, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .build()
    }
}
