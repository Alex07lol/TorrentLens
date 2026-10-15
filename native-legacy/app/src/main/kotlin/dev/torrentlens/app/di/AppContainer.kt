package dev.torrentlens.app.di

import android.content.Context
import dev.torrentlens.app.service.Notifications
import dev.torrentlens.app.work.ManifestCheckScheduler
import dev.torrentlens.core.data.db.TorrentLensDatabase
import dev.torrentlens.core.data.repo.LibraryRepository
import dev.torrentlens.core.data.repo.SubscriptionRepository
import dev.torrentlens.core.data.repo.TorrentTaskRepository
import dev.torrentlens.core.data.settings.SettingsStore
import dev.torrentlens.core.github.GitHubReleaseClient
import dev.torrentlens.core.github.UpdateChecker
import dev.torrentlens.core.torrent.engine.EngineOptions
import dev.torrentlens.core.torrent.engine.LibtorrentEngine
import dev.torrentlens.core.torrent.engine.TorrentEngine
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Publisher keys TorrentLens trusts when verifying a signed release manifest.
 *
 * This is the trust root, so it is a compile-time constant: a manifest can never
 * introduce the key that verifies it. Empty by default — with no pinned key,
 * signed manifests are reported as `unsigned` rather than trusted, which is the
 * fail-closed behaviour.
 */
object TrustedPublisherKeys {
    val PINNED: Set<String> = emptySet()
}

/** Signals that the engine is (not yet) usable, so the UI can say so honestly. */
enum class EngineStatus { STARTING, RUNNING, FAILED, STOPPED }

class AppContainer(private val context: Context) {

    val database: TorrentLensDatabase = TorrentLensDatabase.build(context)

    val taskRepository = TorrentTaskRepository(database.torrentTaskDao())
    val libraryRepository = LibraryRepository(database.libraryDao())
    val subscriptionRepository = SubscriptionRepository(database.subscriptionDao())

    val settingsStore = SettingsStore(context)

    val engine: TorrentEngine = LibtorrentEngine()
    val githubClient = GitHubReleaseClient()
    val updateChecker = UpdateChecker(githubClient, TrustedPublisherKeys.PINNED)

    /**
     * Where torrent payload is written. App-specific external storage needs no
     * runtime permission; the user's chosen Storage Access Framework location is
     * the *export* target, because libtorrent writes through plain file paths.
     */
    val downloadRoot: File =
        context.getExternalFilesDir("TorrentLens") ?: File(context.filesDir, "TorrentLens")

    /** Scratch space for reading archives and documents that need a real file. */
    val cacheRoot: File = File(context.cacheDir, "reader").apply { mkdirs() }

    val applicationContext: Context get() = context.applicationContext

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private val _engineStatus = MutableStateFlow(EngineStatus.STOPPED)
    val engineStatus: StateFlow<EngineStatus> = _engineStatus.asStateFlow()

    fun bootstrap() {
        Notifications.ensureChannels(context)
        ManifestCheckScheduler.schedule(context, checkIntervalMinutes = 1440)
        startEngine()
        persistEngineStatus()
    }

    fun startEngine() {
        if (_engineStatus.value == EngineStatus.STARTING || _engineStatus.value == EngineStatus.RUNNING) return
        _engineStatus.value = EngineStatus.STARTING
        scope.launch {
            runCatching {
                val current = settingsStore.current()
                engine.start(
                    EngineOptions(
                        sessionDownloadLimitBytesPerSec = current.globalDownloadLimitBytesPerSec,
                        sessionUploadLimitBytesPerSec = current.globalUploadLimitBytesPerSec,
                        enableDht = true,
                        enableLsd = true,
                    ),
                )
            }.onSuccess {
                _engineStatus.value = EngineStatus.RUNNING
            }.onFailure {
                _engineStatus.value = EngineStatus.FAILED
            }
        }
    }

    /**
     * Mirrors engine status into the database so a process restart can rebuild
     * the task list even though the in-memory handles are gone.
     */
    private fun persistEngineStatus() {
        scope.launch {
            runCatching {
                engine.observeStatus().collect { snapshot ->
                    snapshot.forEach { (infoHash, stats) ->
                        runCatching { taskRepository.updateStats(infoHash, stats) }
                    }
                }
            }
        }
    }
}
