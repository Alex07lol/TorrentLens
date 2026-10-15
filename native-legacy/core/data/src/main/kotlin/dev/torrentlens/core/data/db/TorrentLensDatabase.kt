package dev.torrentlens.core.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [
        TorrentTaskEntity::class,
        TorrentFileEntity::class,
        LibraryItemEntity::class,
        ReadingProgressEntity::class,
        BookmarkEntity::class,
        SubscriptionEntity::class,
        ReleaseEntity::class,
    ],
    version = 1,
    exportSchema = true,
)
abstract class TorrentLensDatabase : RoomDatabase() {
    abstract fun torrentTaskDao(): TorrentTaskDao
    abstract fun libraryDao(): LibraryDao
    abstract fun subscriptionDao(): SubscriptionDao
    abstract fun dashboardDao(): DashboardDao

    companion object {
        const val NAME = "torrentlens.db"

        fun build(context: Context): TorrentLensDatabase =
            Room.databaseBuilder(context.applicationContext, TorrentLensDatabase::class.java, NAME)
                // No destructive fallback: a metadata wipe would lose the record of
                // what was downloaded and where. Migrations are added explicitly.
                .build()
    }
}
