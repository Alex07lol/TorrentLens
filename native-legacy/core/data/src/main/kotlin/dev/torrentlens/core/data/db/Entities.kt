package dev.torrentlens.core.data.db

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Room entities. Enums are persisted as their `name` string rather than via
 * TypeConverters so a schema change is visible in the SQL and a rename is an
 * explicit migration decision instead of a silent ordinal shift.
 */
@Entity(tableName = "torrent_tasks")
data class TorrentTaskEntity(
    @PrimaryKey val id: String,
    val infoHash: String,
    val displayName: String,
    val magnetUri: String?,
    val torrentFileUri: String?,
    /** SAF tree URI chosen by the user for this task. */
    val downloadDirUri: String?,
    val state: String,
    val progress: Double,
    val downloadedBytes: Long,
    val totalBytes: Long,
    val downloadRate: Long,
    val uploadRate: Long,
    val numPeers: Int,
    val numSeeds: Int,
    val errorMessage: String?,
    val addedAt: Long,
    val updatedAt: Long,
    val uploadLimitBytesPerSec: Long,
    val downloadLimitBytesPerSec: Long,
    val seedingEnabled: Boolean,
    val seedRatioLimit: Double?,
    val seedForMinutes: Int?,
)

@Entity(
    tableName = "torrent_task_files",
    primaryKeys = ["taskId", "relativePath"],
    indices = [Index("taskId")],
)
data class TorrentFileEntity(
    val taskId: String,
    val relativePath: String,
    val sizeBytes: Long,
    val selected: Boolean,
    val isPaddingFile: Boolean,
)

@Entity(tableName = "library_items", indices = [Index("kind")])
data class LibraryItemEntity(
    @PrimaryKey val id: String,
    val title: String,
    val kind: String,
    val contentUri: String,
    val sizeBytes: Long,
    val addedAt: Long,
    val sourceTaskId: String?,
    val coverPath: String?,
)

@Entity(tableName = "reading_progress")
data class ReadingProgressEntity(
    @PrimaryKey val libraryItemId: String,
    val locator: String,
    val percent: Double,
    val mode: String,
    val direction: String,
    val updatedAt: Long,
)

@Entity(tableName = "bookmarks", indices = [Index("libraryItemId")])
data class BookmarkEntity(
    @PrimaryKey val id: String,
    val libraryItemId: String,
    val locator: String,
    val label: String?,
    val createdAt: Long,
)

@Entity(tableName = "subscriptions", indices = [Index(value = ["owner", "repo"], unique = true)])
data class SubscriptionEntity(
    @PrimaryKey val id: String,
    val owner: String,
    val repo: String,
    val displayName: String,
    val includePrereleases: Boolean,
    val checkIntervalMinutes: Int,
    val autoDownload: Boolean,
    val lastCheckedAt: Long?,
    val lastError: String?,
    val installedVersion: String?,
)

@Entity(tableName = "releases", indices = [Index("subscriptionId")])
data class ReleaseEntity(
    @PrimaryKey val id: String,
    val subscriptionId: String,
    val tag: String,
    val name: String?,
    val publishedAt: Long,
    val prerelease: Boolean,
    val manifestVersion: String?,
    val verification: String,
    val notes: String?,
    val downloadUrl: String?,
    val isInstalled: Boolean,
)
