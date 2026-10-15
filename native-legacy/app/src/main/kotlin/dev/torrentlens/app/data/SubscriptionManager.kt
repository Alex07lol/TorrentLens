package dev.torrentlens.app.data

import dev.torrentlens.app.di.AppContainer
import dev.torrentlens.core.domain.github.GitHubRef
import dev.torrentlens.core.domain.github.GitHubRefException
import dev.torrentlens.core.domain.github.GitHubRefParseResult
import dev.torrentlens.core.domain.model.GitHubSubscription
import dev.torrentlens.core.domain.model.ReleaseRecord
import dev.torrentlens.core.github.UpdateCheckOutcome
import java.util.UUID

/**
 * Owns subscriptions: adding a repository, running checks, and recording what
 * was seen.
 *
 * Notifications are emitted only for genuinely new releases, which is why
 * [dev.torrentlens.core.data.repo.SubscriptionRepository.recordRelease] reports
 * whether the row was new. Auto-download is honoured only when the user enabled
 * it on that specific subscription.
 */
class SubscriptionManager(private val container: AppContainer) {

    suspend fun addRepository(input: String): Result<GitHubSubscription> {
        val parsed = GitHubRef.parse(input)
        val ref: GitHubRef = when (parsed) {
            is GitHubRefParseResult.Valid -> parsed.ref
            is GitHubRefParseResult.Invalid -> return Result.failure(GitHubRefException(parsed.error))
        }
        // Identity is owner/repo, case-insensitively, matching GitHub.
        val subscription = GitHubSubscription(
            id = "${ref.owner.lowercase()}/${ref.repo.lowercase()}",
            owner = ref.owner,
            repo = ref.repo,
            displayName = ref.slug,
            includePrereleases = false,
            checkIntervalMinutes = 1440,
            autoDownload = false,
        )
        container.subscriptionRepository.add(subscription)
        return Result.success(subscription)
    }

    suspend fun check(subscriptionId: String): UpdateCheckOutcome {
        val subscription = container.subscriptionRepository.findById(subscriptionId)
            ?: return UpdateCheckOutcome.Skipped("That subscription no longer exists.")

        val outcome = container.updateChecker.check(subscription)

        when (outcome) {
            is UpdateCheckOutcome.UpdateFound -> {
                val isNew = container.subscriptionRepository.recordRelease(
                    ReleaseRecord(
                        id = "$subscriptionId#${outcome.tag}",
                        subscriptionId = subscriptionId,
                        tag = outcome.tag,
                        name = outcome.tag,
                        publishedAtEpochMillis = System.currentTimeMillis(),
                        prerelease = false,
                        manifestVersion = outcome.version,
                        verification = outcome.verification,
                        notes = null,
                        downloadUrl = outcome.decision.applicableArtifact?.url,
                        isInstalled = false,
                    ),
                )
                if (isNew) {
                    container.subscriptionRepository.recordCheck(
                        subscriptionId, System.currentTimeMillis(), outcome.version, null,
                    )
                }
            }
            is UpdateCheckOutcome.Current -> container.subscriptionRepository.recordCheck(
                subscriptionId, System.currentTimeMillis(), outcome.version, null,
            )
            is UpdateCheckOutcome.Failed -> container.subscriptionRepository.recordCheck(
                subscriptionId, System.currentTimeMillis(), null, outcome.message,
            )
            is UpdateCheckOutcome.Rejected -> container.subscriptionRepository.recordCheck(
                subscriptionId, System.currentTimeMillis(), null,
                "Release rejected: ${outcome.reason}",
            )
            is UpdateCheckOutcome.Skipped -> Unit
        }
        return outcome
    }

    /** Runs every due subscription. Returns how many actually produced a change. */
    suspend fun checkAll(): Int {
        var updates = 0
        container.subscriptionRepository.findScheduled().forEach { subscription ->
            when (check(subscription.id)) {
                is UpdateCheckOutcome.UpdateFound -> updates++
                else -> Unit
            }
        }
        return updates
    }

    fun newId(): String = UUID.randomUUID().toString()
}
