package dev.torrentlens.core.github

import dev.torrentlens.core.domain.github.GitHubRef
import dev.torrentlens.core.domain.github.ManifestDiscovery
import dev.torrentlens.core.domain.github.ManifestRejection
import dev.torrentlens.core.domain.github.SemanticVersion
import dev.torrentlens.core.domain.github.UpdateDecision
import dev.torrentlens.core.domain.github.UpdateEvaluator
import dev.torrentlens.core.domain.github.UpdateManifest
import dev.torrentlens.core.domain.model.GitHubSubscription
import dev.torrentlens.core.domain.security.DetachedSignature
import dev.torrentlens.core.domain.security.PublisherSignatureVerifier
import dev.torrentlens.core.domain.security.SignatureReason
import dev.torrentlens.core.domain.security.SignatureVerdict
import kotlinx.serialization.json.Json
import java.nio.charset.StandardCharsets

/** Outcome of a single subscription check. */
sealed interface UpdateCheckOutcome {
    data class UpdateFound(
        val version: String,
        val tag: String,
        val decision: UpdateDecision.UpdateAvailable,
        val verification: String,
    ) : UpdateCheckOutcome

    data class Current(val version: String, val checkedAtEpochMillis: Long) : UpdateCheckOutcome

    data class Skipped(val reason: String) : UpdateCheckOutcome

    data class Failed(val message: String, val rateLimit: RateLimit? = null) : UpdateCheckOutcome

    /** The publisher's manifest failed verification. This is a hard stop. */
    data class Rejected(val reason: ManifestRejection, val detail: String) : UpdateCheckOutcome
}

/**
 * Turns a subscription into a verified update decision.
 *
 * Order is deliberate and fail-closed:
 *   1. list releases
 *   2. pick the newest non-draft release (prereleases only if opted in)
 *   3. discover an explicit manifest asset (never guess)
 *   4. verify the manifest's detached Ed25519 signature against pinned keys
 *   5. only then trust the version it declares
 *
 * Verification never depends on the data being verified: the trust root is a
 * compile-time constant supplied by the caller.
 */
class UpdateChecker(
    private val client: GitHubReleaseClient,
    private val trustedPublisherKeysHex: Set<String>,
    private val json: Json = Json { ignoreUnknownKeys = true; explicitNulls = false },
    private val now: () -> Long = System::currentTimeMillis,
) {

    suspend fun check(subscription: GitHubSubscription): UpdateCheckOutcome {
        val ref: GitHubRef = subscription.ref
            ?: return UpdateCheckOutcome.Failed("'${subscription.owner}/${subscription.repo}' is not a valid repository.")

        val releases = when (val r = client.listReleases(ref, includePrereleases = subscription.includePrereleases)) {
            is GitHubResult.Err -> return when (val e = r.error) {
                is GitHubError.RateLimited -> UpdateCheckOutcome.Failed(
                    "GitHub rate limit reached. Try again after the reset.", e.rateLimit,
                )
                is GitHubError.Http -> UpdateCheckOutcome.Failed("GitHub returned HTTP ${e.code}.")
                is GitHubError.Network -> UpdateCheckOutcome.Failed("Network error: ${e.message}")
                is GitHubError.Malformed -> UpdateCheckOutcome.Failed(e.message)
            }
            is GitHubResult.Ok -> r.value
        }

        if (releases.isEmpty()) return UpdateCheckOutcome.Skipped("No published releases to check.")

        // Newest by our version ordering, not by release id.
        val newest = releases.maxWithOrNull { a, b ->
            dev.torrentlens.core.domain.github.ReleaseVersionComparator.compare(a.tagName, b.tagName)
        } ?: return UpdateCheckOutcome.Skipped("No comparable releases.")

        val discovery = ManifestDiscovery.discover(newest.assets.map { it.name })
        val manifestAsset = when (discovery) {
            is ManifestDiscovery.Result.NotFound ->
                return UpdateCheckOutcome.Skipped("Release ${newest.tagName} publishes no TorrentLens manifest.")
            is ManifestDiscovery.Result.Ambiguous ->
                return UpdateCheckOutcome.Rejected(
                    ManifestRejection.UNSUPPORTED_SCHEMA,
                    "Release publishes several candidate manifests (${discovery.candidates.joinToString()}); refusing to guess.",
                )
            is ManifestDiscovery.Result.Found -> newest.assets.first { it.name.endsWith(discovery.assetName) }
        }

        val manifestBytes = when (val r = client.downloadAsset(manifestAsset.downloadUrl)) {
            is GitHubResult.Err -> return UpdateCheckOutcome.Failed("Could not download the manifest.")
            is GitHubResult.Ok -> r.value
        }

        // Signature is a sibling `.sig` asset: it signs the exact manifest bytes,
        // which an inline signature field could not do without canonicalisation.
        val signatureAsset = newest.assets.firstOrNull { it.name == "${manifestAsset.name}.sig" }
        val verification: String
        if (signatureAsset != null) {
            val sigBytes = when (val r = client.downloadAsset(signatureAsset.downloadUrl)) {
                is GitHubResult.Err -> return UpdateCheckOutcome.Failed("Could not download the manifest signature.")
                is GitHubResult.Ok -> r.value
            }
            val detached = runCatching {
                json.decodeFromString(DetachedSignature.serializer(), String(sigBytes, StandardCharsets.UTF_8))
            }.getOrNull() ?: return UpdateCheckOutcome.Rejected(
                ManifestRejection.SIGNATURE_INVALID, "The signature asset is malformed.",
            )
            when (val verdict = PublisherSignatureVerifier.verify(manifestBytes, detached, trustedPublisherKeysHex)) {
                is SignatureVerdict.Valid -> verification = "verified"
                is SignatureVerdict.Invalid -> return UpdateCheckOutcome.Rejected(
                    ManifestRejection.SIGNATURE_INVALID, describe(verdict.reason),
                )
            }
        } else {
            // Unsigned manifests are reported as such; an unsigned update is only
            // ever offered as a manual action, never auto-installed.
            verification = "unsigned"
        }

        val manifest = runCatching {
            json.decodeFromString(UpdateManifest.serializer(), String(manifestBytes, StandardCharsets.UTF_8))
        }.getOrNull() ?: return UpdateCheckOutcome.Rejected(
            ManifestRejection.UNSUPPORTED_SCHEMA, "The manifest is not valid JSON in the expected schema.",
        )

        val installed = subscription.installedVersion
            ?: return UpdateCheckOutcome.UpdateFound(
                version = manifest.version,
                tag = newest.tagName,
                decision = UpdateDecision.UpdateAvailable(
                    installedVersion = "unknown",
                    latestVersion = manifest.version,
                    manifest = manifest,
                    applicableArtifact = manifest.pickAndroidArtifact(),
                ),
                verification = verification,
            )

        return when (val decision = UpdateEvaluator.evaluate(installed, manifest)) {
            is UpdateDecision.UpdateAvailable -> UpdateCheckOutcome.UpdateFound(
                version = decision.latestVersion,
                tag = newest.tagName,
                decision = decision,
                verification = verification,
            )
            is UpdateDecision.UpToDate -> UpdateCheckOutcome.Current(decision.version, now())
            is UpdateDecision.InstalledIsNewer -> UpdateCheckOutcome.Current(decision.installedVersion, now())
            is UpdateDecision.Rejected -> UpdateCheckOutcome.Rejected(decision.reason, "Manifest rejected.")
        }
    }

    private fun UpdateManifest.pickAndroidArtifact() =
        artifacts.firstOrNull { it.platform == "android" && it.abi == "arm64-v8a" }
            ?: artifacts.firstOrNull { it.platform == "android" }
            ?: artifacts.firstOrNull { it.platform == null }

    private fun describe(reason: SignatureReason): String = when (reason) {
        SignatureReason.UNSUPPORTED_ALGORITHM -> "The manifest is signed with an unsupported algorithm."
        SignatureReason.MALFORMED_PUBLIC_KEY -> "The signing key in the manifest is malformed."
        SignatureReason.MALFORMED_SIGNATURE -> "The manifest signature is malformed."
        SignatureReason.NO_TRUSTED_KEY -> "The manifest was signed by a key TorrentLens does not trust."
        SignatureReason.SIGNATURE_MISMATCH -> "The manifest signature does not match its contents."
    }

    /** Convenience for UI that just needs a version string comparison. */
    fun isNewer(candidate: String, installed: String): Boolean {
        val a = SemanticVersion.parse(candidate) ?: return false
        val b = SemanticVersion.parse(installed) ?: return true
        return a > b
    }
}
