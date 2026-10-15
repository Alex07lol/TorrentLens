package dev.torrentlens.app.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import dev.torrentlens.app.data.SubscriptionManager
import dev.torrentlens.app.data.TorrentImporter
import dev.torrentlens.app.di.AppContainer
import dev.torrentlens.app.di.EngineStatus
import dev.torrentlens.core.data.repo.TorrentTaskRecord
import dev.torrentlens.core.data.settings.AppSettings
import dev.torrentlens.core.domain.model.GitHubSubscription
import dev.torrentlens.core.domain.model.LibraryItem
import dev.torrentlens.core.domain.model.ReadingDirection
import dev.torrentlens.core.domain.model.ReadingMode
import dev.torrentlens.core.domain.model.SelectedFile
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** A one-shot message for snackbars; cleared once shown. */
data class UiMessage(val text: String, val isError: Boolean = false)

/**
 * One ViewModel for the whole shell.
 *
 * The app's state is a handful of flows over the same container, and every screen
 * already observes only what it needs. A single VM keeps the wiring honest and
 * avoids five near-identical classes; screen-level ViewModels can be split out
 * later without touching the data layer.
 */
class TorrentLensViewModel(private val container: AppContainer) : ViewModel() {

    private val importer = TorrentImporter(container)
    private val subscriptions = SubscriptionManager(container)

    val engineStatus: StateFlow<EngineStatus> = container.engineStatus

    val tasks: StateFlow<List<TorrentTaskRecord>> = container.taskRepository.observeAll()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val library: StateFlow<List<LibraryItem>> = container.libraryRepository.observeAll()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val subscriptionsList: StateFlow<List<GitHubSubscription>> = container.subscriptionRepository.observeAll()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val settings: StateFlow<AppSettings> = container.settingsStore.settings
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AppSettings())

    private val _message = MutableStateFlow<UiMessage?>(null)
    val message: StateFlow<UiMessage?> = _message.asStateFlow()

    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()

    private val selectedTaskId = MutableStateFlow<String?>(null)

    /** File list for the task currently open in the file-selection sheet. */
    val taskFiles: StateFlow<List<SelectedFile>> = selectedTaskId
        .flatMapLatest { id -> if (id == null) flowOf(emptyList()) else container.taskRepository.observeFiles(id) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    fun clearMessage() { _message.value = null }

    fun openFileSelection(taskId: String?) { selectedTaskId.value = taskId }

    // ---- torrents ---------------------------------------------------------

    fun importTorrent(input: String) {
        if (input.isBlank()) {
            _message.value = UiMessage("Paste a magnet link, a torrent URL, or pick a .torrent file.", isError = true)
            return
        }
        viewModelScope.launch {
            _busy.value = true
            importer.import(input)
                .onSuccess { result ->
                    _message.value = UiMessage(
                        if (result.fileCount > 0) {
                            "Added ${result.displayName} (${result.fileCount} files)."
                        } else {
                            "Added ${result.displayName}. Fetching metadata…"
                        },
                    )
                }
                .onFailure { error ->
                    _message.value = UiMessage(error.message ?: "That torrent could not be added.", isError = true)
                }
            _busy.value = false
        }
    }

    fun pauseTask(id: String) = viewModelScope.launch {
        container.engine.pause(id).onFailure { _message.value = UiMessage(it.message ?: "Could not pause.", true) }
    }

    fun resumeTask(id: String) = viewModelScope.launch {
        container.engine.resume(id).onFailure { _message.value = UiMessage(it.message ?: "Could not resume.", true) }
    }

    fun removeTask(id: String, deleteFiles: Boolean) = viewModelScope.launch {
        container.engine.remove(id, deleteFiles)
        container.taskRepository.remove(id)
        _message.value = UiMessage("Removed from the list.")
    }

    fun setFileSelected(taskId: String, path: String, selected: Boolean) = viewModelScope.launch {
        container.taskRepository.setFileSelected(taskId, path, selected)
        val current = taskFiles.value
        val chosen = current.filter { it.selected || it.relativePath == path }.map { it.relativePath }.toSet()
        container.engine.setFileSelection(taskId, chosen)
    }

    fun applyFileSelection(taskId: String) = viewModelScope.launch {
        val chosen = taskFiles.value.filter { it.selected }.map { it.relativePath }.toSet()
        container.engine.setFileSelection(taskId, chosen)
            .onSuccess { _message.value = UiMessage("Downloading ${chosen.size} file(s).") }
            .onFailure { _message.value = UiMessage(it.message ?: "Could not apply the selection.", true) }
        selectedTaskId.value = null
    }

    // ---- subscriptions ----------------------------------------------------

    fun addSubscription(input: String) = viewModelScope.launch {
        subscriptions.addRepository(input)
            .onSuccess { _message.value = UiMessage("Following ${it.displayName}.") }
            .onFailure { _message.value = UiMessage(it.message ?: "That repository could not be followed.", isError = true) }
    }

    fun removeSubscription(id: String) = viewModelScope.launch {
        container.subscriptionRepository.remove(id)
    }

    fun checkSubscription(id: String) = viewModelScope.launch {
        _busy.value = true
        when (val outcome = subscriptions.check(id)) {
            is dev.torrentlens.core.github.UpdateCheckOutcome.UpdateFound ->
                _message.value = UiMessage("${outcome.version} is available (${outcome.verification}).")
            is dev.torrentlens.core.github.UpdateCheckOutcome.Current ->
                _message.value = UiMessage("Already up to date.")
            is dev.torrentlens.core.github.UpdateCheckOutcome.Skipped ->
                _message.value = UiMessage(outcome.reason)
            is dev.torrentlens.core.github.UpdateCheckOutcome.Failed ->
                _message.value = UiMessage(outcome.message, isError = true)
            is dev.torrentlens.core.github.UpdateCheckOutcome.Rejected ->
                _message.value = UiMessage("Release rejected: ${outcome.reason}", isError = true)
        }
        _busy.value = false
    }

    fun checkAllSubscriptions() = viewModelScope.launch {
        _busy.value = true
        val updates = runCatching { subscriptions.checkAll() }.getOrElse { 0 }
        _message.value = if (updates > 0) UiMessage("$updates new release(s) found.") else UiMessage("No new releases.")
        _busy.value = false
    }

    // ---- library ----------------------------------------------------------

    fun addToLibrary(item: LibraryItem) = viewModelScope.launch {
        container.libraryRepository.add(item)
        _message.value = UiMessage("Added ${item.title} to the library.")
    }

    fun removeFromLibrary(id: String) = viewModelScope.launch { container.libraryRepository.remove(id) }

    fun saveReadingProgress(itemId: String, locator: String, percent: Double, mode: ReadingMode, direction: ReadingDirection) =
        viewModelScope.launch {
            container.libraryRepository.saveProgress(itemId, locator, percent, mode, direction)
        }

    fun addBookmark(itemId: String, locator: String, label: String?) = viewModelScope.launch {
        container.libraryRepository.addBookmark(itemId, locator, label)
        _message.value = UiMessage("Bookmark saved.")
    }

    // ---- settings ---------------------------------------------------------

    fun setThemeDark(dark: Boolean?) = viewModelScope.launch { container.settingsStore.setThemeDark(dark) }
    fun setDownloadLimit(bytesPerSec: Long) = viewModelScope.launch {
        container.settingsStore.setDownloadLimit(bytesPerSec)
        container.engine.setSessionLimits(bytesPerSec, settings.value.globalUploadLimitBytesPerSec)
    }
    fun setUploadLimit(bytesPerSec: Long) = viewModelScope.launch {
        container.settingsStore.setUploadLimit(bytesPerSec)
        container.engine.setSessionLimits(settings.value.globalDownloadLimitBytesPerSec, bytesPerSec)
    }
    fun setWifiOnly(enabled: Boolean) = viewModelScope.launch { container.settingsStore.setWifiOnly(enabled) }
    fun setSeedAfterComplete(enabled: Boolean) = viewModelScope.launch { container.settingsStore.setSeedAfterComplete(enabled) }
    fun setDefaultReading(mode: ReadingMode, direction: ReadingDirection) = viewModelScope.launch {
        container.settingsStore.setDefaultReading(mode, direction)
    }
    fun setDefaultDownloadDir(uri: String?) = viewModelScope.launch { container.settingsStore.setDefaultDownloadDir(uri) }

    companion object {
        fun factory(container: AppContainer): ViewModelProvider.Factory = viewModelFactory {
            initializer { TorrentLensViewModel(container) }
        }
    }
}
