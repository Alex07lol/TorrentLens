package dev.torrentlens.core.data.repo

import dev.torrentlens.core.data.db.BookmarkEntity
import dev.torrentlens.core.data.db.LibraryDao
import dev.torrentlens.core.data.db.LibraryItemEntity
import dev.torrentlens.core.data.db.ReadingProgressEntity
import dev.torrentlens.core.domain.model.Bookmark
import dev.torrentlens.core.domain.model.LibraryItem
import dev.torrentlens.core.domain.model.MediaKind
import dev.torrentlens.core.domain.model.ReadingDirection
import dev.torrentlens.core.domain.model.ReadingMode
import dev.torrentlens.core.domain.model.ReadingProgress
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class LibraryRepository(
    private val dao: LibraryDao,
    private val now: () -> Long = System::currentTimeMillis,
) {

    fun observeAll(): Flow<List<LibraryItem>> = dao.observeAll().map { rows -> rows.map { it.toDomain() } }

    suspend fun findById(id: String): LibraryItem? = dao.findById(id)?.toDomain()

    suspend fun add(item: LibraryItem) = dao.upsert(
        LibraryItemEntity(
            id = item.id,
            title = item.title,
            kind = item.kind.name,
            contentUri = item.contentUri,
            sizeBytes = item.sizeBytes,
            addedAt = item.addedAtEpochMillis,
            sourceTaskId = item.sourceTaskId,
            coverPath = item.coverPath,
        ),
    )

    suspend fun remove(id: String) = dao.delete(id)

    fun observeProgress(itemId: String): Flow<ReadingProgress?> =
        dao.observeProgress(itemId).map { it?.toDomain() }

    suspend fun findProgress(itemId: String): ReadingProgress? = dao.findProgress(itemId)?.toDomain()

    /**
     * Reading position is written on every page turn, so it is stored as a
     * single upsert keyed by item and is safe to call at high frequency.
     */
    suspend fun saveProgress(
        itemId: String,
        locator: String,
        percent: Double,
        mode: ReadingMode,
        direction: ReadingDirection,
    ) = dao.upsertProgress(
        ReadingProgressEntity(
            libraryItemId = itemId,
            locator = locator,
            percent = percent.coerceIn(0.0, 1.0),
            mode = mode.name,
            direction = direction.name,
            updatedAt = now(),
        ),
    )

    fun observeBookmarks(itemId: String): Flow<List<Bookmark>> =
        dao.observeBookmarks(itemId).map { rows ->
            rows.map { Bookmark(it.id, it.libraryItemId, it.locator, it.label, it.createdAt) }
        }

    suspend fun addBookmark(itemId: String, locator: String, label: String?) = dao.upsertBookmark(
        BookmarkEntity(
            id = "$itemId#$locator",
            libraryItemId = itemId,
            locator = locator,
            label = label,
            createdAt = now(),
        ),
    )

    suspend fun removeBookmark(id: String) = dao.deleteBookmark(id)

    private fun LibraryItemEntity.toDomain() = LibraryItem(
        id = id,
        title = title,
        kind = runCatching { MediaKind.valueOf(kind) }.getOrDefault(MediaKind.UNKNOWN),
        contentUri = contentUri,
        sizeBytes = sizeBytes,
        addedAtEpochMillis = addedAt,
        sourceTaskId = sourceTaskId,
        coverPath = coverPath,
    )

    private fun ReadingProgressEntity.toDomain() = ReadingProgress(
        libraryItemId = libraryItemId,
        locator = locator,
        percent = percent,
        updatedAtEpochMillis = updatedAt,
        mode = runCatching { ReadingMode.valueOf(mode) }.getOrDefault(ReadingMode.PAGED),
        direction = runCatching { ReadingDirection.valueOf(direction) }
            .getOrDefault(ReadingDirection.LEFT_TO_RIGHT),
    )
}
