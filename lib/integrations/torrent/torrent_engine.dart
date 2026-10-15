import 'package:flutter/services.dart';

/// Session options applied when the native engine starts.
class EngineOptions {
  final int downloadLimitBps;
  final int uploadLimitBps;
  final bool enableDht;
  final int maxActiveDownloads;
  const EngineOptions({
    this.downloadLimitBps = 0,
    this.uploadLimitBps = 0,
    this.enableDht = true,
    this.maxActiveDownloads = 3,
  });
}

class TorrentMetadataFile {
  final int index;
  final String path;
  final String? originalPath;
  final int sizeBytes;
  final bool isPadding;
  const TorrentMetadataFile({
    required this.index,
    required this.path,
    required this.sizeBytes,
    this.originalPath,
    this.isPadding = false,
  });
}

class TorrentMetadata {
  final List<TorrentMetadataFile> files;
  /// Entries the sanitizer rejected (traversal, absolute paths, duplicates…).
  /// Surfaced to the user rather than silently dropped.
  final List<String> rejected;
  const TorrentMetadata({required this.files, this.rejected = const []});

  int get totalBytes => files.fold(0, (sum, f) => sum + f.sizeBytes);
}

class EngineStatus {
  final String infoHash;
  final String state;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final int downloadBps;
  final int uploadBps;
  final int numPeers;
  final int numSeeds;
  final String? errorMessage;
  const EngineStatus({
    required this.infoHash,
    required this.state,
    required this.progress,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.downloadBps,
    required this.uploadBps,
    required this.numPeers,
    required this.numSeeds,
    this.errorMessage,
  });

  static EngineStatus fromMap(Map<Object?, Object?> m) => EngineStatus(
        infoHash: '${m['infoHash']}',
        state: '${m['state']}',
        progress: (m['progress'] as num?)?.toDouble() ?? 0,
        downloadedBytes: (m['downloadedBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (m['totalBytes'] as num?)?.toInt() ?? 0,
        downloadBps: (m['downloadBps'] as num?)?.toInt() ?? 0,
        uploadBps: (m['uploadBps'] as num?)?.toInt() ?? 0,
        numPeers: (m['numPeers'] as num?)?.toInt() ?? 0,
        numSeeds: (m['numSeeds'] as num?)?.toInt() ?? 0,
        errorMessage: m['errorMessage'] as String?,
      );
}

/// What a play-while-downloading session could read from disk right now.
///
/// These are measurements taken by the native engine, not conclusions. The
/// policy that turns them into "buffering" or "ready to play" lives in
/// `lib/domain/torrent/streaming.dart`, where it is unit-tested without a
/// device.
class StreamSnapshot {
  final String infoHash;

  /// Sanitized path relative to the download directory. This is the stable key
  /// for a file: the engine's own index shifts when a torrent's file list has
  /// entries rejected by the sanitizer.
  final String relativePath;
  final int fileIndex;
  final int fileLengthBytes;
  final int fileOffsetInTorrent;
  final int pieceLength;
  final int firstFilePiece;
  final int lastFilePiece;
  final int fileDoneBytes;
  final bool fileComplete;
  final int rangeFirstPiece;
  final int rangeLastPiece;

  /// Piece indices inside the requested range that are already verified on disk.
  final List<int> piecesHave;
  final int downloadBps;
  final int uploadBps;
  final int numPeers;
  final int numSeeds;
  final String state;
  final double progress;

  const StreamSnapshot({
    required this.infoHash,
    required this.relativePath,
    required this.fileIndex,
    required this.fileLengthBytes,
    required this.fileOffsetInTorrent,
    required this.pieceLength,
    required this.firstFilePiece,
    required this.lastFilePiece,
    required this.fileDoneBytes,
    required this.fileComplete,
    required this.rangeFirstPiece,
    required this.rangeLastPiece,
    required this.piecesHave,
    required this.downloadBps,
    required this.uploadBps,
    required this.numPeers,
    required this.numSeeds,
    required this.state,
    required this.progress,
  });

  Set<int> get piecesHaveSet => piecesHave.toSet();

  static StreamSnapshot fromMap(Map<Object?, Object?> m) => StreamSnapshot(
        infoHash: '${m['infoHash']}',
        relativePath: '${m['relativePath']}',
        fileIndex: (m['fileIndex'] as num?)?.toInt() ?? -1,
        fileLengthBytes: (m['fileLengthBytes'] as num?)?.toInt() ?? 0,
        fileOffsetInTorrent: (m['fileOffsetInTorrent'] as num?)?.toInt() ?? 0,
        pieceLength: (m['pieceLength'] as num?)?.toInt() ?? 0,
        firstFilePiece: (m['firstFilePiece'] as num?)?.toInt() ?? 0,
        lastFilePiece: (m['lastFilePiece'] as num?)?.toInt() ?? 0,
        fileDoneBytes: (m['fileDoneBytes'] as num?)?.toInt() ?? 0,
        fileComplete: m['fileComplete'] == true,
        rangeFirstPiece: (m['rangeFirstPiece'] as num?)?.toInt() ?? 0,
        rangeLastPiece: (m['rangeLastPiece'] as num?)?.toInt() ?? 0,
        piecesHave:
            (m['piecesHave'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const <int>[],
        downloadBps: (m['downloadBps'] as num?)?.toInt() ?? 0,
        uploadBps: (m['uploadBps'] as num?)?.toInt() ?? 0,
        numPeers: (m['numPeers'] as num?)?.toInt() ?? 0,
        numSeeds: (m['numSeeds'] as num?)?.toInt() ?? 0,
        state: '${m['state']}',
        progress: (m['progress'] as num?)?.toDouble() ?? 0,
      );
}

/// The torrent engine contract the app depends on. The native implementation
/// talks to Kotlin over a platform channel; tests supply their own fake.
abstract class TorrentEngine {
  Future<bool> isRunning();
  Future<void> start(EngineOptions options);
  Future<void> stop();

  /// Resolves metadata from a magnet and adds it. Returns the v1 info-hash hex.
  Future<String> addMagnet(String magnetUri, String savePath);

  /// Adds an already-read `.torrent` descriptor. Returns the v1 info-hash hex.
  Future<String> addTorrentFile(Uint8List bytes, String savePath);

  Future<TorrentMetadata> metadata(String infoHash);

  /// Selects the files to download, by their sanitized relative paths.
  Future<void> setFileSelection(String infoHash, Set<String> relativePaths);

  Future<void> pause(String infoHash);
  Future<void> resume(String infoHash);
  Future<void> remove(String infoHash);

  /// Re-checks on-disk data (used after an interrupted session).
  Future<void> recheck(String infoHash);

  Future<void> setTaskLimits(String infoHash,
      {required int uploadLimitBps, required int downloadLimitBps});
  Future<void> setSessionLimits({required int downloadLimitBps, required int uploadLimitBps});

  Future<List<EngineStatus>> allStatus();
  Future<EngineStatus?> status(String infoHash);
  Future<void> addTracker(String infoHash, String announceUrl);
  Future<List<String>> trackers(String infoHash);

  /// Raises the playhead window over [relativePath] to top priority and reports
  /// what is readable now. Absolute piece indices, computed by the caller from
  /// the playback position.
  Future<StreamSnapshot> beginStreaming(
    String infoHash,
    String relativePath, {
    required int firstPiece,
    required int lastPiece,
    required int deadlineMs,
    required int stepMs,
  });

  /// The same measurements without changing priorities, for the polling loop.
  Future<StreamSnapshot> streamSnapshot(
    String infoHash,
    String relativePath, {
    required int firstPiece,
    required int lastPiece,
  });

  /// Releases the window and restores the file's previous priority.
  Future<void> endStreaming(String infoHash, String relativePath);
}

class TorrentEngineException implements Exception {
  final String code;
  final String message;
  const TorrentEngineException(this.code, this.message);
  @override
  String toString() => 'TorrentEngineException($code): $message';
}

/// Talks to the Kotlin engine in `android/app/.../torrent/TorrentEnginePlugin.kt`.
class MethodChannelTorrentEngine implements TorrentEngine {
  static const MethodChannel _channel = MethodChannel('dev.torrentlens/torrent');

  @override
  Future<bool> isRunning() async => (await _channel.invokeMethod<bool>('isRunning')) ?? false;

  @override
  Future<void> start(EngineOptions options) => _invoke('start', {
        'downloadLimit': options.downloadLimitBps,
        'uploadLimit': options.uploadLimitBps,
        'enableDht': options.enableDht,
        'maxActiveDownloads': options.maxActiveDownloads,
      });

  @override
  Future<void> stop() => _invoke('stop');

  @override
  Future<String> addMagnet(String magnetUri, String savePath) async =>
      '${await _invoke('addMagnet', {'magnet': magnetUri, 'savePath': savePath})}';

  @override
  Future<String> addTorrentFile(Uint8List bytes, String savePath) async =>
      '${await _invoke('addTorrentFile', {'bytes': bytes, 'savePath': savePath})}';

  @override
  Future<TorrentMetadata> metadata(String infoHash) async {
    final raw = await _invoke('metadata', {'infoHash': infoHash});
    final map = (raw as Map).cast<Object?, Object?>();
    final files = (map['files'] as List?)
            ?.map((e) {
              final f = (e as Map).cast<Object?, Object?>();
              return TorrentMetadataFile(
                index: (f['index'] as num?)?.toInt() ?? 0,
                path: '${f['path']}',
                originalPath: f['originalPath'] as String?,
                sizeBytes: (f['sizeBytes'] as num?)?.toInt() ?? 0,
                isPadding: f['isPadding'] == true,
              );
            })
            .toList() ??
        const <TorrentMetadataFile>[];
    final rejected = (map['rejected'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    return TorrentMetadata(files: files, rejected: rejected);
  }

  @override
  Future<void> setFileSelection(String infoHash, Set<String> relativePaths) =>
      _invoke('setFileSelection', {'infoHash': infoHash, 'paths': relativePaths.toList()});

  @override
  Future<void> pause(String infoHash) => _invoke('pause', {'infoHash': infoHash});
  @override
  Future<void> resume(String infoHash) => _invoke('resume', {'infoHash': infoHash});
  @override
  Future<void> remove(String infoHash) => _invoke('remove', {'infoHash': infoHash});
  @override
  Future<void> recheck(String infoHash) => _invoke('recheck', {'infoHash': infoHash});

  @override
  Future<void> setTaskLimits(String infoHash,
          {required int uploadLimitBps, required int downloadLimitBps}) =>
      _invoke('setTaskLimits', {
        'infoHash': infoHash,
        'uploadLimit': uploadLimitBps,
        'downloadLimit': downloadLimitBps,
      });

  @override
  Future<void> setSessionLimits(
          {required int downloadLimitBps, required int uploadLimitBps}) =>
      _invoke('setSessionLimits', {
        'downloadLimit': downloadLimitBps,
        'uploadLimit': uploadLimitBps,
      });

  @override
  Future<List<EngineStatus>> allStatus() async {
    final raw = await _invoke('allStatus');
    return (raw as List? ?? const [])
        .map((e) => EngineStatus.fromMap((e as Map).cast<Object?, Object?>()))
        .toList();
  }

  @override
  Future<EngineStatus?> status(String infoHash) async {
    final raw = await _invoke('status', {'infoHash': infoHash});
    if (raw == null) return null;
    return EngineStatus.fromMap((raw as Map).cast<Object?, Object?>());
  }

  @override
  Future<void> addTracker(String infoHash, String announceUrl) =>
      _invoke('addTracker', {'infoHash': infoHash, 'url': announceUrl});

  @override
  Future<List<String>> trackers(String infoHash) async {
    final raw = await _invoke('trackers', {'infoHash': infoHash});
    return (raw as List? ?? const []).map((e) => '$e').toList();
  }

  @override
  Future<StreamSnapshot> beginStreaming(
    String infoHash,
    String relativePath, {
    required int firstPiece,
    required int lastPiece,
    required int deadlineMs,
    required int stepMs,
  }) async {
    final raw = await _invoke('beginStreaming', {
      'infoHash': infoHash,
      'path': relativePath,
      'firstPiece': firstPiece,
      'lastPiece': lastPiece,
      'deadlineMs': deadlineMs,
      'stepMs': stepMs,
    });
    return StreamSnapshot.fromMap((raw as Map).cast<Object?, Object?>());
  }

  @override
  Future<StreamSnapshot> streamSnapshot(
    String infoHash,
    String relativePath, {
    required int firstPiece,
    required int lastPiece,
  }) async {
    final raw = await _invoke('streamSnapshot', {
      'infoHash': infoHash,
      'path': relativePath,
      'firstPiece': firstPiece,
      'lastPiece': lastPiece,
    });
    return StreamSnapshot.fromMap((raw as Map).cast<Object?, Object?>());
  }

  @override
  Future<void> endStreaming(String infoHash, String relativePath) =>
      _invoke('endStreaming', {'infoHash': infoHash, 'path': relativePath});

  Future<Object?> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } on PlatformException catch (e) {
      throw TorrentEngineException(e.code, e.message ?? 'torrent engine error');
    } on MissingPluginException {
      throw const TorrentEngineException(
          'ENGINE_UNAVAILABLE', 'The native torrent engine is not available on this platform.');
    }
  }
}
