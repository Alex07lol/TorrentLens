package dev.torrentlens.torrentlens.torrent

import android.os.Handler
import android.os.Looper
import dev.torrentlens.torrentlens.service.TorrentDownloadService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Platform channel for the native torrent engine.
 *
 * Channel: `dev.torrentlens/torrent`.
 *
 * Every engine call runs on a single background thread because the libtorrent4j
 * SWIG layer blocks and is not safe to drive from the UI thread; the reply is
 * always posted back to the main looper, which is where `MethodChannel.Result`
 * must be completed.
 */
class TorrentEnginePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private val io: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "torrent-engine").apply { isDaemon = true }
    }
    private val main = Handler(Looper.getMainLooper())

    private val engine get() = EngineHolder.engine

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        EngineHolder.context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "isRunning") {
            result.success(engine.isRunning)
            return
        }
        if (call.method == "stop") {
            io.execute {
                engine.stop()
                EngineHolder.context?.let { TorrentDownloadService.stop(it) }
                main.post { result.success(null) }
            }
            return
        }
        io.execute {
            try {
                val value = dispatch(call)
                main.post { result.success(value) }
            } catch (failure: EngineFailure) {
                main.post { result.error(failure.error.name, failure.message, null) }
            } catch (t: Throwable) {
                main.post { result.error("INTERNAL", t.message ?: "torrent engine error", null) }
            }
        }
    }

    private fun dispatch(call: MethodCall): Any? = when (call.method) {
        "start" -> {
            val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
            engine.start(
                EngineOptions(
                    sessionDownloadLimitBytesPerSec = (args["downloadLimit"] as? Number)?.toLong() ?: 0,
                    sessionUploadLimitBytesPerSec = (args["uploadLimit"] as? Number)?.toLong() ?: 0,
                    enableDht = args["enableDht"] as? Boolean ?: true,
                    maxActiveDownloads = (args["maxActiveDownloads"] as? Number)?.toInt() ?: 3,
                ),
            )
            null
        }
        "addMagnet" -> {
            val magnet = require(call, "magnet")
            val savePath = require(call, "savePath")
            EngineHolder.context?.let { TorrentDownloadService.start(it, "Resolving metadata") }
            unwrap(engine.addMagnet(magnet, File(savePath)))
        }
        "addTorrentFile" -> {
            val bytes = call.argument<ByteArray>("bytes")
                ?: throw EngineFailure(EngineError.INVALID_DESCRIPTOR)
            val savePath = require(call, "savePath")
            EngineHolder.context?.let { TorrentDownloadService.start(it, "Adding torrent") }
            unwrap(engine.addTorrentFile(bytes, File(savePath)))
        }
        "metadata" -> mapOf(
            "files" to engine.metadata(require(call, "infoHash")),
            "rejected" to engine.lastRejected.get(),
        )
        "setFileSelection" -> unwrap(
            engine.setFileSelection(
                require(call, "infoHash"),
                (call.argument<List<String>>("paths") ?: emptyList()).toSet(),
            ),
        )
        "pause" -> unwrap(engine.pause(require(call, "infoHash")))
        "resume" -> unwrap(engine.resume(require(call, "infoHash")))
        "remove" -> unwrap(engine.remove(require(call, "infoHash")))
        "recheck" -> unwrap(engine.recheck(require(call, "infoHash")))
        "setTaskLimits" -> unwrap(
            engine.setTaskLimits(
                require(call, "infoHash"),
                (call.argument<Number>("uploadLimit") ?: 0).toLong(),
                (call.argument<Number>("downloadLimit") ?: 0).toLong(),
            ),
        )
        "setSessionLimits" -> {
            engine.setSessionLimits(
                (call.argument<Number>("downloadLimit") ?: 0).toLong(),
                (call.argument<Number>("uploadLimit") ?: 0).toLong(),
            )
            null
        }
        "allStatus" -> engine.allStatus().map { EngineHolder.taskStatusToMap(it) }
        "status" -> engine.status(require(call, "infoHash"))?.let { EngineHolder.taskStatusToMap(it) }
        "addTracker" -> unwrap(engine.addTracker(require(call, "infoHash"), require(call, "url")))
        "trackers" -> engine.trackers(require(call, "infoHash"))
        "beginStreaming" -> {
            val infoHash = require(call, "infoHash")
            // Playback of a partially downloaded file is an active transfer, so
            // it must be visible in the notification shade like any other.
            EngineHolder.context?.let { TorrentDownloadService.start(it, "Streaming ${call.argument<String>("path") ?: "media"}") }
            EngineHolder.streamSnapshotToMap(
                unwrap(
                    engine.beginStreaming(
                        infoHashHex = infoHash,
                        relativePath = require(call, "path"),
                        firstPiece = call.argument<Number>("firstPiece")?.toInt() ?: 0,
                        lastPiece = call.argument<Number>("lastPiece")?.toInt() ?: 0,
                        deadlineMs = call.argument<Number>("deadlineMs")?.toInt() ?: DEFAULT_DEADLINE_MS,
                        stepMs = call.argument<Number>("stepMs")?.toInt() ?: DEFAULT_STEP_MS,
                    ),
                ),
            )
        }
        "streamSnapshot" -> EngineHolder.streamSnapshotToMap(
            unwrap(
                engine.streamSnapshot(
                    infoHashHex = require(call, "infoHash"),
                    relativePath = require(call, "path"),
                    firstPiece = call.argument<Number>("firstPiece")?.toInt() ?: 0,
                    lastPiece = call.argument<Number>("lastPiece")?.toInt() ?: 0,
                ),
            ),
        )
        "endStreaming" -> unwrap(engine.endStreaming(require(call, "infoHash"), require(call, "path")))
        else -> throw IllegalArgumentException("unknown method ${call.method}")
    }

    private fun require(call: MethodCall, name: String): String =
        call.argument<String>(name) ?: throw IllegalArgumentException("$name is required")

    /**
     * Unwraps an engine result of any type, so a caller that needs the concrete
     * value (the streaming snapshots) does not have to cast it back.
     */
    private fun <T> unwrap(result: Result<T>): T = result.fold(
        onSuccess = { it },
        onFailure = { t ->
            throw (t as? EngineFailure) ?: EngineFailure(EngineError.INTERNAL, t)
        },
    )

    companion object {
        const val CHANNEL = "dev.torrentlens/torrent"

        /**
         * Streaming priority defaults. Dart owns these numbers in
         * `StreamingPolicy`; they are repeated here only so a call that omits
         * them still behaves sanely.
         */
        const val DEFAULT_DEADLINE_MS = 1_500
        const val DEFAULT_STEP_MS = 250
    }
}
