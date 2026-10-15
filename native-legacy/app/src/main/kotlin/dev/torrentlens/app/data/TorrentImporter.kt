package dev.torrentlens.app.data

import android.net.Uri
import android.provider.OpenableColumns
import dev.torrentlens.app.di.AppContainer
import dev.torrentlens.core.domain.model.TorrentTaskOptions
import dev.torrentlens.core.domain.torrent.TorrentInputError
import dev.torrentlens.core.domain.torrent.TorrentInputException
import dev.torrentlens.core.domain.torrent.TorrentSource
import dev.torrentlens.core.domain.torrent.TorrentSourceClassifier
import java.io.File
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Turns pasted text or a picked document into a running task.
 *
 * Every input is classified first (see `TorrentSourceClassifier`), so an
 * unsupported scheme or a malformed info-hash fails before any network or engine
 * work happens.
 */
class TorrentImporter(private val container: AppContainer) {

    private val http = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .callTimeout(60, TimeUnit.SECONDS)
        .build()

    /** Maximum size of a `.torrent` descriptor we will read. */
    private val maxDescriptorBytes = 4L * 1024 * 1024

    sealed interface Imported {
        data class Task(val infoHash: String, val displayName: String, val fileCount: Int, val totalBytes: Long) : Imported
    }

    suspend fun import(input: String): Result<Imported.Task> = withContext(Dispatchers.IO) {
        val source = TorrentSourceClassifier.classify(input).getOrElse { error ->
            return@withContext Result.failure(
                TorrentInputException(error as? TorrentInputError ?: TorrentInputError.UnrecognizedInput),
            )
        }

        val downloadDir = File(container.downloadRoot, "incoming").apply { mkdirs() }

        val infoHash = when (source) {
            is TorrentSource.Magnet -> container.engine.addMagnet(source.original, downloadDir)
            is TorrentSource.Remote -> fetchRemoteDescriptor(source.url).mapCatching { bytes ->
                container.engine.addTorrentFile(bytes, downloadDir)
            }.fold(
                onSuccess = { it },
                onFailure = { return@withContext Result.failure(it) },
            )
            is TorrentSource.LocalFile -> readLocalDescriptor(source.location).mapCatching { bytes ->
                container.engine.addTorrentFile(bytes, downloadDir)
            }.fold(
                onSuccess = { it },
                onFailure = { return@withContext Result.failure(it) },
            )
            is TorrentSource.Bytes -> container.engine.addTorrentFile(source.content, downloadDir)
        }.getOrElse { return@withContext Result.failure(it) }

        val metadata = container.engine.metadata(infoHash)
        val displayName = when (source) {
            is TorrentSource.Magnet -> source.uri.displayName
            is TorrentSource.Remote -> source.url.substringAfterLast('/').ifBlank { infoHash }
            is TorrentSource.LocalFile -> source.displayName
            is TorrentSource.Bytes -> source.displayName
        } ?: infoHash

        container.taskRepository.add(
            id = infoHash,
            infoHash = infoHash,
            displayName = displayName,
            magnetUri = (source as? TorrentSource.Magnet)?.original,
            torrentFileUri = (source as? TorrentSource.LocalFile)?.location,
            downloadDirUri = downloadDir.absolutePath,
            options = TorrentTaskOptions(seedingEnabled = true),
        )

        if (metadata != null) {
            container.taskRepository.replaceFiles(
                infoHash,
                metadata.accepted.map {
                    dev.torrentlens.core.domain.model.SelectedFile(it.relativePath, it.lengthBytes, selected = true)
                },
            )
        }

        Result.success(
            Imported.Task(
                infoHash = infoHash,
                displayName = displayName,
                fileCount = metadata?.accepted?.size ?: 0,
                totalBytes = metadata?.totalBytes ?: 0,
            ),
        )
    }

    private fun fetchRemoteDescriptor(url: String): Result<ByteArray> = runCatching {
        val request = Request.Builder().url(url).header("User-Agent", "TorrentLens/0.1").get().build()
        http.newCall(request).execute().use { response ->
            require(response.isSuccessful) { "HTTP ${response.code} while fetching the torrent file" }
            val declared = response.header("Content-Length")?.toLongOrNull()
            require(declared == null || declared <= maxDescriptorBytes) { "Torrent descriptor is too large" }
            val bytes = response.body?.bytes() ?: error("Empty response")
            require(bytes.size <= maxDescriptorBytes) { "Torrent descriptor is too large" }
            bytes
        }
    }

    private fun readLocalDescriptor(location: String): Result<ByteArray> = runCatching {
        val uri = Uri.parse(location)
        if (uri.scheme == "content") {
            container.applicationContext.contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input) { "Could not open the selected document" }
                val bytes = input.readBytes()
                require(bytes.size <= maxDescriptorBytes) { "Torrent descriptor is too large" }
                bytes
            }
        } else {
            val file = File(uri.path ?: location)
            require(file.length() in 1..maxDescriptorBytes) { "Torrent descriptor is missing or too large" }
            file.readBytes()
        }
    }

    /** Best-effort display name for a picked document. */
    fun displayNameOf(uri: Uri): String? = runCatching {
        container.applicationContext.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
    }.getOrNull()
}
