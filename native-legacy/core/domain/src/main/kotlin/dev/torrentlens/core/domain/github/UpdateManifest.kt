package dev.torrentlens.core.domain.github

import dev.torrentlens.core.domain.security.DetachedSignature
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * The explicit version manifest a subscribed repository publishes.
 *
 * Discovery is deliberately *explicit* (`ignoreUnknownKeys` is on, but required
 * fields are required): we never infer an update from a tag's text alone, and we
 * never treat an arbitrary release asset as installable. Metadata (this file)
 * and the torrent/file distribution channel stay separate components — the
 * manifest names the torrent or artifact, it does not carry the payload.
 */
@Serializable
data class UpdateManifest(
    @SerialName("schema_version") val schemaVersion: Int,
    val version: String,
    @SerialName("published_at") val publishedAt: String? = null,
    val notes: String? = null,
    val artifacts: List<ManifestArtifact> = emptyList(),
    /** Detached signature over the canonical manifest body, if the publisher signs. */
    val signature: DetachedSignature? = null,
) {
    fun parsedVersion(): SemanticVersion? = SemanticVersion.parse(version)

    companion object {
        /** Bumped only for breaking changes to the manifest schema. */
        const val SUPPORTED_SCHEMA_VERSION = 1
    }
}

@Serializable
data class ManifestArtifact(
    val name: String,
    val url: String,
    @SerialName("size_bytes") val sizeBytes: Long? = null,
    @SerialName("sha256") val sha256: String? = null,
    /** e.g. "android", "windows", "linux" — used to pick what to offer on this device. */
    val platform: String? = null,
    /** e.g. "arm64-v8a". */
    val abi: String? = null,
    /** When the payload is distributed as a torrent, its magnet URI. */
    @SerialName("magnet") val magnet: String? = null,
)

/** Result of comparing the installed version with a freshly fetched manifest. */
sealed interface UpdateDecision {
    data class UpdateAvailable(
        val installedVersion: String,
        val latestVersion: String,
        val manifest: UpdateManifest,
        val applicableArtifact: ManifestArtifact?,
    ) : UpdateDecision

    data class UpToDate(val version: String) : UpdateDecision

    data class InstalledIsNewer(val installedVersion: String, val manifestVersion: String) : UpdateDecision

    /** The manifest was fetched but cannot be trusted or understood. */
    data class Rejected(val reason: ManifestRejection) : UpdateDecision
}

enum class ManifestRejection {
    UNSUPPORTED_SCHEMA,
    UNPARSEABLE_VERSION,
    SIGNATURE_INVALID,
    MISSING_ARTIFACT_FOR_PLATFORM,
}

object UpdateEvaluator {

    /**
     * Pure comparison step. The caller is responsible for having verified the
     * manifest's signature and integrity *before* calling this, so that
     * verification never depends on the content it is validating.
     *
     * @param installedVersion the version string currently stored in the app DB.
     * @param platform filter for artifacts; artifacts with a null platform are
     *   treated as platform-agnostic and always eligible.
     */
    fun evaluate(
        installedVersion: String,
        manifest: UpdateManifest,
        platform: String = "android",
    ): UpdateDecision {
        if (manifest.schemaVersion > UpdateManifest.SUPPORTED_SCHEMA_VERSION) {
            return UpdateDecision.Rejected(ManifestRejection.UNSUPPORTED_SCHEMA)
        }
        val latest = manifest.parsedVersion()
            ?: return UpdateDecision.Rejected(ManifestRejection.UNPARSEABLE_VERSION)

        val installed = SemanticVersion.parse(installedVersion)
        if (installed == null) {
            // Unknown installed version: treat the manifest as newer rather than
            // risking a silently stuck install.
            return UpdateDecision.UpdateAvailable(
                installedVersion, latest.original, manifest, manifest.applicableArtifact(platform),
            )
        }

        return when {
            latest > installed -> UpdateDecision.UpdateAvailable(
                installed.original, latest.original, manifest, manifest.applicableArtifact(platform),
            )
            latest < installed -> UpdateDecision.InstalledIsNewer(installed.original, latest.original)
            else -> UpdateDecision.UpToDate(installed.original)
        }
    }

    private fun UpdateManifest.applicableArtifact(platform: String): ManifestArtifact? {
        val exact = artifacts.filter { it.platform.equals(platform, ignoreCase = true) }
        // arm64 first: it is the only ABI we ship for release today.
        return exact.firstOrNull { it.abi == "arm64-v8a" }
            ?: exact.firstOrNull()
            ?: artifacts.firstOrNull { it.platform == null }
    }
}

/**
 * Picks the manifest file out of a GitHub release's asset list.
 *
 * Deterministic preference order, and *no* guessing: if the publisher ships
 * several files that all look like manifests we surface the ambiguity instead of
 * silently picking one, because choosing the wrong file would mean verifying the
 * wrong file.
 */
object ManifestDiscovery {

    /** Ordered by preference; the first name that matches wins. */
    val CANONICAL_NAMES = listOf(
        "torrentlens-manifest.json",
        "update-manifest.json",
        "manifest.json",
    )

    sealed interface Result {
        data class Found(val assetName: String, val tier: Tier) : Result
        data class Ambiguous(val candidates: List<String>) : Result
        data object NotFound : Result
    }

    enum class Tier { CANONICAL, CONVENTION }

    fun discover(assetNames: List<String>): Result {
        val normalized = assetNames.map { it.substringAfterLast('/') }
        for (canonical in CANONICAL_NAMES) {
            val hit = normalized.firstOrNull { it.equals(canonical, ignoreCase = true) }
            if (hit != null) return Result.Found(hit, Tier.CANONICAL)
        }
        // Fall back to the `*.manifest.json` convention, but only when unique.
        val conventional = normalized.filter { it.lowercase().endsWith(".manifest.json") }
        return when (conventional.size) {
            0 -> Result.NotFound
            1 -> Result.Found(conventional.first(), Tier.CONVENTION)
            else -> Result.Ambiguous(conventional)
        }
    }
}
