package dev.torrentlens.core.data.repo

import dev.torrentlens.core.data.db.TorrentFileEntity
import dev.torrentlens.core.data.db.TorrentTaskDao
import dev.torrentlens.core.data.db.TorrentTaskEntity
import dev.torrentlens.core.domain.model.SelectedFile
import dev.torrentlens.core.domain.model.TorrentTaskOptions
import dev.torrentlens.core.domain.model.TorrentTaskState
import dev.torrentlens.core.domain.model.TorrentTaskStats
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Domain-facing view of a persisted task. */
data class TorrentTaskRecord(
    val id: String,
    val infoHash: String,
    val displayName: String,
    val magnetUri: String?,
    val torrentFileUri: String?,
    val downloadDirUri: String?,
    val stats: TorrentTaskStats,
    val options: TorrentTaskOptions,
    val addedAt: Long,
    val updatedAt: Long,
)

class TorrentTaskRepository(
    private val dao: TorrentTaskDao,
    private val now: () -> Long = System::currentTimeMillis,
) {

    fun observeAll(): Flow<List<TorrentTaskRecord>> = dao.observeAll().map { it.map { it.toRecord() } }

    fun observeActive(): Flow<List<TorrentTaskRecord>> = dao.observeActive().map { it.map { it.toRecord() } }

    fun observeFiles(taskId: String): Flow<List<SelectedFile>> =
        dao.observeFiles(taskId).map { rows -> rows.map { SelectedFile(it.relativePath, it.sizeBytes, it.selected) } }

    suspend fun findById(id: String): TorrentTaskRecord? = dao.findById(id)?.toRecord()

    suspend fun findUnfinished(): List<TorrentTaskRecord> = dao.findUnfinished().map { it.toRecord() }

    suspend fun add(
        id: String,
        infoHash: String,
        displayName: String,
        magnetUri: String?,
        torrentFileUri: String?,
        downloadDirUri: String?,
        options: TorrentTaskOptions = TorrentTaskOptions(),
    ) {
        val timestamp = now()
        dao.upsert(
            TorrentTaskEntity(
                id = id,
                infoHash = infoHash,
                displayName = displayName,
                magnetUri = magnetUri,
                torrentFileUri = torrentFileUri,
                downloadDirUri = downloadDirUri,
                state = TorrentTaskState.METADATA.name,
                progress = 0.0,
                downloadedBytes = 0,
                totalBytes = 0,
                downloadRate = 0,
                uploadRate = 0,
                numPeers = 0,
                numSeeds = 0,
                errorMessage = null,
                addedAt = timestamp,
                updatedAt = timestamp,
                uploadLimitBytesPerSec = options.uploadLimitBytesPerSec,
                downloadLimitBytesPerSec = options.downloadLimitBytesPerSec,
                seedingEnabled = options.seedingEnabled,
                seedRatioLimit = options.seedRatioLimit,
                seedForMinutes = options.seedForMinutes,
            ),
        )
    }

    /**
     * Writes only status columns. Progress callbacks are frequent and must not
     * overwrite the user's file selection or per-task settings.
     */
    suspend fun updateStats(id: String, stats: TorrentTaskStats) {
        dao.updateStats(
            id = id,
            state = stats.state.name,
            progress = stats.progress,
            downloaded = stats.downloadedBytes,
            total = stats.totalBytes,
            downloadRate = stats.downloadRateBytesPerSec,
            uploadRate = stats.uploadRateBytesPerSec,
            peers = stats.numPeers,
            seeds = stats.numSeeds,
            error = stats.errorMessage,
            now = now(),
        )
    }

    suspend fun setOptions(id: String, options: TorrentTaskOptions) {
        val current = dao.findById(id) ?: return
        dao.upsert(
            current.copy(
                uploadLimitBytesPerSec = options.uploadLimitBytesPerSec,
                downloadLimitBytesPerSec = options.downloadLimitBytesPerSec,
                seedingEnabled = options.seedingEnabled,
                seedRatioLimit = options.seedRatioLimit,
                seedForMinutes = options.seedForMinutes,
                updatedAt = now(),
            ),
        )
    }

    suspend fun replaceFiles(taskId: String, files: List<SelectedFile>) {
        dao.deleteFiles(taskId)
        dao.upsertFiles(
            files.map {
                TorrentFileEntity(
                    taskId = taskId,
                    relativePath = it.relativePath,
                    sizeBytes = it.sizeBytes,
                    selected = it.selected,
                    isPaddingFile = false,
                )
            },
        )
    }

    suspend fun setFileSelected(taskId: String, path: String, selected: Boolean) =
        dao.setFileSelected(taskId, path, selected)

    suspend fun remove(id: String) {
        dao.deleteFiles(id)
        dao.delete(id)
    }

    private fun TorrentTaskEntity.toRecord() = TorrentTaskRecord(
        id = id,
        infoHash = infoHash,
        displayName = displayName,
        magnetUri = magnetUri,
        torrentFileUri = torrentFileUri,
        downloadDirUri = downloadDirUri,
        stats = TorrentTaskStats(
            progress = progress,
            downloadedBytes = downloadedBytes,
            totalBytes = totalBytes,
            downloadRateBytesPerSec = downloadRate,
            uploadRateBytesPerSec = uploadRate,
            numPeers = numPeers,
            numSeeds = numSeeds,
            state = runCatching { TorrentTaskState.valueOf(state) }.getOrDefault(TorrentTaskState.QUEUED),
            errorMessage = errorMessage,
        ),
        options = TorrentTaskOptions(
            uploadLimitBytesPerSec = uploadLimitBytesPerSec,
            downloadLimitBytesPerSec = downloadLimitBytesPerSec,
            seedingEnabled = seedingEnabled,
            seedRatioLimit = seedRatioLimit,
            seedForMinutes = seedForMinutes,
        ),
        addedAt = addedAt,
        updatedAt = updatedAt,
    )
}
