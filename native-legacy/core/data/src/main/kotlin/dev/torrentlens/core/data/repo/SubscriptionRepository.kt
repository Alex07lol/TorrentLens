package dev.torrentlens.core.data.repo

import dev.torrentlens.core.data.db.ReleaseEntity
import dev.torrentlens.core.data.db.SubscriptionDao
import dev.torrentlens.core.data.db.SubscriptionEntity
import dev.torrentlens.core.domain.model.GitHubSubscription
import dev.torrentlens.core.domain.model.ReleaseRecord
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class SubscriptionRepository(private val dao: SubscriptionDao) {

    fun observeAll(): Flow<List<GitHubSubscription>> =
        dao.observeAll().map { rows -> rows.map { it.toDomain() } }

    suspend fun findScheduled(): List<GitHubSubscription> = dao.findScheduled().map { it.toDomain() }

    suspend fun findById(id: String): GitHubSubscription? = dao.findById(id)?.toDomain()

    suspend fun add(subscription: GitHubSubscription) = dao.upsert(
        SubscriptionEntity(
            id = subscription.id,
            owner = subscription.owner,
            repo = subscription.repo,
            displayName = subscription.displayName,
            includePrereleases = subscription.includePrereleases,
            checkIntervalMinutes = subscription.checkIntervalMinutes,
            autoDownload = subscription.autoDownload,
            lastCheckedAt = subscription.lastCheckedAtEpochMillis,
            lastError = subscription.lastError,
            installedVersion = subscription.installedVersion,
        ),
    )

    suspend fun recordCheck(id: String, checkedAt: Long, installedVersion: String?, error: String?) {
        val current = dao.findById(id) ?: return
        dao.upsert(
            current.copy(
                lastCheckedAt = checkedAt,
                installedVersion = installedVersion ?: current.installedVersion,
                lastError = error,
            ),
        )
    }

    suspend fun remove(id: String) = dao.delete(id)

    /**
     * Persists a release, returning true only the first time it is seen so the
     * notification path cannot fire twice for the same release.
     */
    suspend fun recordRelease(release: ReleaseRecord): Boolean {
        val isNew = dao.releaseExists(release.id) == 0
        dao.upsertRelease(
            ReleaseEntity(
                id = release.id,
                subscriptionId = release.subscriptionId,
                tag = release.tag,
                name = release.name,
                publishedAt = release.publishedAtEpochMillis,
                prerelease = release.prerelease,
                manifestVersion = release.manifestVersion,
                verification = release.verification,
                notes = release.notes,
                downloadUrl = release.downloadUrl,
                isInstalled = release.isInstalled,
            ),
        )
        return isNew
    }

    fun observeReleases(subscriptionId: String): Flow<List<ReleaseRecord>> =
        dao.observeReleases(subscriptionId).map { rows ->
            rows.map {
                ReleaseRecord(
                    id = it.id,
                    subscriptionId = it.subscriptionId,
                    tag = it.tag,
                    name = it.name,
                    publishedAtEpochMillis = it.publishedAt,
                    prerelease = it.prerelease,
                    manifestVersion = it.manifestVersion,
                    verification = it.verification,
                    notes = it.notes,
                    downloadUrl = it.downloadUrl,
                    isInstalled = it.isInstalled,
                )
            }
        }

    private fun SubscriptionEntity.toDomain() = GitHubSubscription(
        id = id,
        owner = owner,
        repo = repo,
        displayName = displayName,
        includePrereleases = includePrereleases,
        checkIntervalMinutes = checkIntervalMinutes,
        autoDownload = autoDownload,
        lastCheckedAtEpochMillis = lastCheckedAt,
        lastError = lastError,
        installedVersion = installedVersion,
    )
}
