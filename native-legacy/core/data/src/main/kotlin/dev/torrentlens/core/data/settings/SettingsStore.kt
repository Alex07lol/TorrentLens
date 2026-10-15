package dev.torrentlens.core.data.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dev.torrentlens.core.domain.model.ReadingDirection
import dev.torrentlens.core.domain.model.ReadingMode
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(name = "torrentlens_settings")

data class AppSettings(
    val themeDark: Boolean? = null,
    val defaultDownloadDirUri: String? = null,
    /** 0 = unlimited. */
    val globalDownloadLimitBytesPerSec: Long = 0,
    val globalUploadLimitBytesPerSec: Long = 0,
    val seedAfterComplete: Boolean = true,
    val defaultReadingMode: ReadingMode = ReadingMode.PAGED,
    val defaultReadingDirection: ReadingDirection = ReadingDirection.LEFT_TO_RIGHT,
    val wifiOnlyDownloads: Boolean = false,
    val autoCheckUpdates: Boolean = true,
    /** Minutes between scheduled manifest checks; 0 disables. */
    val updateCheckIntervalMinutes: Int = 1440,
)

/** Small scalar preferences kept out of Room. */
class SettingsStore(private val context: Context) {

    val settings: Flow<AppSettings> = context.settingsDataStore.data.map { p ->
        AppSettings(
            themeDark = p[KEY_THEME_DARK],
            defaultDownloadDirUri = p[KEY_DOWNLOAD_DIR],
            globalDownloadLimitBytesPerSec = p[KEY_DL_LIMIT] ?: 0,
            globalUploadLimitBytesPerSec = p[KEY_UL_LIMIT] ?: 0,
            seedAfterComplete = p[KEY_SEED] ?: true,
            defaultReadingMode = p[KEY_READ_MODE]?.let { runCatching { ReadingMode.valueOf(it) }.getOrNull() }
                ?: ReadingMode.PAGED,
            defaultReadingDirection = p[KEY_READ_DIR]?.let { runCatching { ReadingDirection.valueOf(it) }.getOrNull() }
                ?: ReadingDirection.LEFT_TO_RIGHT,
            wifiOnlyDownloads = p[KEY_WIFI_ONLY] ?: false,
            autoCheckUpdates = p[KEY_AUTO_CHECK] ?: true,
            updateCheckIntervalMinutes = p[KEY_CHECK_INTERVAL] ?: 1440,
        )
    }

    suspend fun current(): AppSettings = settings.first()

    suspend fun setDefaultDownloadDir(uri: String?) = edit { prefs ->
        if (uri == null) prefs.remove(KEY_DOWNLOAD_DIR) else prefs[KEY_DOWNLOAD_DIR] = uri
    }

    suspend fun setDownloadLimit(bytesPerSec: Long) = edit { it[KEY_DL_LIMIT] = bytesPerSec.coerceAtLeast(0) }

    suspend fun setUploadLimit(bytesPerSec: Long) = edit { it[KEY_UL_LIMIT] = bytesPerSec.coerceAtLeast(0) }

    suspend fun setSeedAfterComplete(enabled: Boolean) = edit { it[KEY_SEED] = enabled }

    suspend fun setWifiOnly(enabled: Boolean) = edit { it[KEY_WIFI_ONLY] = enabled }

    suspend fun setAutoCheckUpdates(enabled: Boolean) = edit { it[KEY_AUTO_CHECK] = enabled }

    suspend fun setUpdateCheckIntervalMinutes(minutes: Int) = edit { it[KEY_CHECK_INTERVAL] = minutes.coerceAtLeast(0) }

    suspend fun setThemeDark(dark: Boolean?) = edit { prefs ->
        if (dark == null) prefs.remove(KEY_THEME_DARK) else prefs[KEY_THEME_DARK] = dark
    }

    suspend fun setDefaultReading(mode: ReadingMode, direction: ReadingDirection) = edit {
        it[KEY_READ_MODE] = mode.name
        it[KEY_READ_DIR] = direction.name
    }

    private suspend fun edit(block: (androidx.datastore.preferences.core.MutablePreferences) -> Unit) {
        context.settingsDataStore.edit(block)
    }

    private companion object {
        val KEY_THEME_DARK = booleanPreferencesKey("theme_dark")
        val KEY_DOWNLOAD_DIR = stringPreferencesKey("default_download_dir")
        val KEY_DL_LIMIT = longPreferencesKey("global_download_limit")
        val KEY_UL_LIMIT = longPreferencesKey("global_upload_limit")
        val KEY_SEED = booleanPreferencesKey("seed_after_complete")
        val KEY_READ_MODE = stringPreferencesKey("reading_mode")
        val KEY_READ_DIR = stringPreferencesKey("reading_direction")
        val KEY_WIFI_ONLY = booleanPreferencesKey("wifi_only")
        val KEY_AUTO_CHECK = booleanPreferencesKey("auto_check_updates")
        val KEY_CHECK_INTERVAL = intPreferencesKey("update_check_interval_minutes")
    }
}
