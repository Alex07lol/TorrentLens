package dev.torrentlens.core.data.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
interface TorrentTaskDao {
    @Query("SELECT * FROM torrent_tasks ORDER BY addedAt DESC")
    fun observeAll(): Flow<List<TorrentTaskEntity>>

    @Query("SELECT * FROM torrent_tasks WHERE state IN ('METADATA','QUEUED','DOWNLOADING','SEEDING')")
    fun observeActive(): Flow<List<TorrentTaskEntity>>

    @Query("SELECT * FROM torrent_tasks WHERE id = :id")
    suspend fun findById(id: String): TorrentTaskEntity?

    /** Unfinished work, used to rebuild engine state after process death. */
    @Query("SELECT * FROM torrent_tasks WHERE state NOT IN ('COMPLETE','ERROR')")
    suspend fun findUnfinished(): List<TorrentTaskEntity>

    @Upsert
    suspend fun upsert(task: TorrentTaskEntity)

    /**
     * Status-only update. Writing whole rows from a high-frequency progress
     * callback would clobber user settings such as the file selection.
     */
    @Query(
        """
        UPDATE torrent_tasks SET
          state = :state, progress = :progress, downloadedBytes = :downloaded,
          totalBytes = :total, downloadRate = :downloadRate, uploadRate = :uploadRate,
          numPeers = :peers, numSeeds = :seeds, errorMessage = :error, updatedAt = :now
        WHERE id = :id
        """,
    )
    suspend fun updateStats(
        id: String,
        state: String,
        progress: Double,
        downloaded: Long,
        total: Long,
        downloadRate: Long,
        uploadRate: Long,
        peers: Int,
        seeds: Int,
        error: String?,
        now: Long,
    )

    @Query("DELETE FROM torrent_tasks WHERE id = :id")
    suspend fun delete(id: String)

    @Query("SELECT * FROM torrent_task_files WHERE taskId = :taskId ORDER BY relativePath")
    fun observeFiles(taskId: String): Flow<List<TorrentFileEntity>>

    @Upsert
    suspend fun upsertFiles(files: List<TorrentFileEntity>)

    @Query("UPDATE torrent_task_files SET selected = :selected WHERE taskId = :taskId AND relativePath = :path")
    suspend fun setFileSelected(taskId: String, path: String, selected: Boolean)

    @Query("DELETE FROM torrent_task_files WHERE taskId = :taskId")
    suspend fun deleteFiles(taskId: String)
}

@Dao
interface LibraryDao {
    @Query("SELECT * FROM library_items ORDER BY addedAt DESC")
    fun observeAll(): Flow<List<LibraryItemEntity>>

    @Query("SELECT * FROM library_items WHERE id = :id")
    suspend fun findById(id: String): LibraryItemEntity?

    @Upsert
    suspend fun upsert(item: LibraryItemEntity)

    @Query("DELETE FROM library_items WHERE id = :id")
    suspend fun delete(id: String)

    @Upsert
    suspend fun upsertProgress(progress: ReadingProgressEntity)

    @Query("SELECT * FROM reading_progress WHERE libraryItemId = :itemId")
    fun observeProgress(itemId: String): Flow<ReadingProgressEntity?>

    @Query("SELECT * FROM reading_progress WHERE libraryItemId = :itemId")
    suspend fun findProgress(itemId: String): ReadingProgressEntity?

    @Upsert
    suspend fun upsertBookmark(bookmark: BookmarkEntity)

    @Query("SELECT * FROM bookmarks WHERE libraryItemId = :itemId ORDER BY createdAt DESC")
    fun observeBookmarks(itemId: String): Flow<List<BookmarkEntity>>

    @Query("DELETE FROM bookmarks WHERE id = :id")
    suspend fun deleteBookmark(id: String)
}

@Dao
interface SubscriptionDao {
    @Query("SELECT * FROM subscriptions ORDER BY owner, repo")
    fun observeAll(): Flow<List<SubscriptionEntity>>

    @Query("SELECT * FROM subscriptions WHERE checkIntervalMinutes > 0")
    suspend fun findScheduled(): List<SubscriptionEntity>

    @Query("SELECT * FROM subscriptions WHERE id = :id")
    suspend fun findById(id: String): SubscriptionEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(subscription: SubscriptionEntity)

    @Query("DELETE FROM subscriptions WHERE id = :id")
    suspend fun delete(id: String)

    @Upsert
    suspend fun upsertRelease(release: ReleaseEntity)

    @Query("SELECT * FROM releases WHERE subscriptionId = :subscriptionId ORDER BY publishedAt DESC")
    fun observeReleases(subscriptionId: String): Flow<List<ReleaseEntity>>

    /** Used to decide whether a release is genuinely new before notifying. */
    @Query("SELECT COUNT(*) FROM releases WHERE id = :id")
    suspend fun releaseExists(id: String): Int
}

/** Cross-table reads used by the dashboard. */
@Dao
interface DashboardDao {
    @Query("SELECT COUNT(*) FROM torrent_tasks WHERE state IN ('METADATA','QUEUED','DOWNLOADING','SEEDING')")
    fun observeActiveCount(): Flow<Int>

    @Query("SELECT COALESCE(SUM(downloadRate), 0) FROM torrent_tasks WHERE state IN ('DOWNLOADING','SEEDING')")
    fun observeTotalDownloadRate(): Flow<Long>

    @Query("SELECT COUNT(*) FROM library_items")
    fun observeLibraryCount(): Flow<Int>

    @Query("SELECT * FROM releases ORDER BY publishedAt DESC LIMIT :limit")
    fun observeRecentReleases(limit: Int): Flow<List<ReleaseEntity>>
}
