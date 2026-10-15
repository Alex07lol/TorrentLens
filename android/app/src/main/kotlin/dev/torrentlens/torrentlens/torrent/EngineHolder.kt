package dev.torrentlens.torrentlens.torrent

import android.content.Context

/**
 * Process-wide engine instance shared by the Flutter plugin and the foreground
 * service, so a transfer keeps running when the app is backgrounded but the
 * process is alive.
 */
object EngineHolder {
    @Volatile
    var engine: LibtorrentEngine = LibtorrentEngine()

    @Volatile
    var context: Context? = null

    fun taskStatusToMap(status: TaskStatus): Map<String, Any?> = mapOf(
        "infoHash" to status.infoHash,
        "state" to status.state,
        "progress" to status.progress,
        "downloadedBytes" to status.downloadedBytes,
        "totalBytes" to status.totalBytes,
        "downloadBps" to status.downloadBps,
        "uploadBps" to status.uploadBps,
        "numPeers" to status.numPeers,
        "numSeeds" to status.numSeeds,
        "errorMessage" to status.errorMessage,
    )

    /**
     * Field names must stay in step with `StreamSnapshot.fromMap` in
     * `lib/integrations/torrent/torrent_engine.dart`.
     */
    fun streamSnapshotToMap(snapshot: StreamSnapshot): Map<String, Any?> = mapOf(
        "infoHash" to snapshot.infoHash,
        "relativePath" to snapshot.relativePath,
        "fileIndex" to snapshot.fileIndex,
        "fileLengthBytes" to snapshot.fileLengthBytes,
        "fileOffsetInTorrent" to snapshot.fileOffsetInTorrent,
        "pieceLength" to snapshot.pieceLength,
        "firstFilePiece" to snapshot.firstFilePiece,
        "lastFilePiece" to snapshot.lastFilePiece,
        "fileDoneBytes" to snapshot.fileDoneBytes,
        "fileComplete" to snapshot.fileComplete,
        "rangeFirstPiece" to snapshot.rangeFirstPiece,
        "rangeLastPiece" to snapshot.rangeLastPiece,
        "piecesHave" to snapshot.piecesHave,
        "downloadBps" to snapshot.downloadBps,
        "uploadBps" to snapshot.uploadBps,
        "numPeers" to snapshot.numPeers,
        "numSeeds" to snapshot.numSeeds,
        "state" to snapshot.state,
        "progress" to snapshot.progress,
    )
}
