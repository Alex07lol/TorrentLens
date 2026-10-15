import 'dart:typed_data';

import 'package:torrentlens/integrations/torrent/torrent_engine.dart';

/// One `beginStreaming` call, so tests can assert which pieces the app asked the
/// engine to prioritise.
class StreamRequestRecord {
  final String infoHash;
  final String relativePath;
  final int firstPiece;
  final int lastPiece;
  final int deadlineMs;
  final int stepMs;

  const StreamRequestRecord({
    required this.infoHash,
    required this.relativePath,
    required this.firstPiece,
    required this.lastPiece,
    required this.deadlineMs,
    required this.stepMs,
  });

  @override
  String toString() => 'StreamRequest($relativePath, $firstPiece..$lastPiece, '
      'deadline=$deadlineMs step=$stepMs)';
}

/// A torrent engine that reports a fixed set of downloaded pieces.
///
/// It is not a simulator of BitTorrent: it answers exactly what the native
/// engine answers, from state the test controls, so the policy and the session
/// controller can be exercised without a device.
class FakeTorrentEngine implements TorrentEngine {
  FakeTorrentEngine({
    required this.fileLengthBytes,
    required this.relativePath,
    this.infoHash = '0123456789abcdef0123456789abcdef01234567',
    this.pieceLength = 100,
    this.fileOffsetInTorrent = 0,
    this.totalPieces,
    this.state = 'downloading',
    this.numPeers = 4,
    this.numSeeds = 1,
    this.downloadBps = 512 * 1024,
    Set<int>? have,
  }) : have = have ?? <int>{};

  final String infoHash;
  final String relativePath;
  final int fileLengthBytes;
  final int pieceLength;
  final int fileOffsetInTorrent;
  final int? totalPieces;

  /// Pieces present on disk. Tests add to this to simulate downloads.
  final Set<int> have;

  String state;
  int numPeers;
  int numSeeds;
  int downloadBps;

  /// When set, every streaming call throws it.
  Object? streamError;

  final List<StreamRequestRecord> beginCalls = <StreamRequestRecord>[];
  int snapshotCalls = 0;
  final List<String> endCalls = <String>[];
  bool running = true;
  bool stopped = false;

  int get firstFilePiece => fileOffsetInTorrent ~/ pieceLength;
  int get lastFilePiece =>
      (fileOffsetInTorrent + (fileLengthBytes > 0 ? fileLengthBytes : 1) - 1) ~/ pieceLength;
  Set<int> get allFilePieces => {
        for (var p = firstFilePiece; p <= lastFilePiece; p++) p,
      };

  StreamSnapshot _snapshot(int firstPiece, int lastPiece) {
    final last = lastPiece >= firstPiece ? lastPiece : firstPiece;
    final done = have.where((p) => p >= firstFilePiece && p <= lastFilePiece).length * pieceLength;
    final complete = fileLengthBytes <= 0 || done >= fileLengthBytes;
    return StreamSnapshot(
      infoHash: infoHash,
      relativePath: relativePath,
      fileIndex: 0,
      fileLengthBytes: fileLengthBytes,
      fileOffsetInTorrent: fileOffsetInTorrent,
      pieceLength: pieceLength,
      firstFilePiece: firstFilePiece,
      lastFilePiece: lastFilePiece,
      fileDoneBytes: done > fileLengthBytes ? fileLengthBytes : done,
      fileComplete: complete,
      rangeFirstPiece: firstPiece,
      rangeLastPiece: last,
      piecesHave: [
        for (var p = firstPiece; p <= last; p++)
          if (have.contains(p)) p,
      ],
      downloadBps: downloadBps,
      uploadBps: 0,
      numPeers: numPeers,
      numSeeds: numSeeds,
      state: state,
      progress: fileLengthBytes <= 0 ? 1 : (done / fileLengthBytes).clamp(0.0, 1.0),
    );
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
    final error = streamError;
    if (error != null) throw error;
    beginCalls.add(StreamRequestRecord(
      infoHash: infoHash,
      relativePath: relativePath,
      firstPiece: firstPiece,
      lastPiece: lastPiece,
      deadlineMs: deadlineMs,
      stepMs: stepMs,
    ));
    return _snapshot(firstPiece, lastPiece);
  }

  @override
  Future<StreamSnapshot> streamSnapshot(
    String infoHash,
    String relativePath, {
    required int firstPiece,
    required int lastPiece,
  }) async {
    final error = streamError;
    if (error != null) throw error;
    snapshotCalls++;
    return _snapshot(firstPiece, lastPiece);
  }

  @override
  Future<void> endStreaming(String infoHash, String relativePath) async {
    endCalls.add(relativePath);
  }

  // ---- the rest of the contract: enough for a session to run, nothing more ----

  @override
  Future<bool> isRunning() async => running;

  @override
  Future<void> start(EngineOptions options) async => running = true;

  @override
  Future<void> stop() async {
    running = false;
    stopped = true;
  }

  @override
  Future<String> addMagnet(String magnetUri, String savePath) async => infoHash;

  @override
  Future<String> addTorrentFile(Uint8List bytes, String savePath) async => infoHash;

  @override
  Future<TorrentMetadata> metadata(String infoHash) async => TorrentMetadata(
        files: [
          TorrentMetadataFile(index: 0, path: relativePath, sizeBytes: fileLengthBytes),
        ],
      );

  @override
  Future<void> setFileSelection(String infoHash, Set<String> relativePaths) async {}

  @override
  Future<void> pause(String infoHash) async {}

  @override
  Future<void> resume(String infoHash) async {}

  @override
  Future<void> remove(String infoHash) async {}

  @override
  Future<void> recheck(String infoHash) async {}

  @override
  Future<void> setTaskLimits(
    String infoHash, {
    required int uploadLimitBps,
    required int downloadLimitBps,
  }) async {}

  @override
  Future<void> setSessionLimits({
    required int downloadLimitBps,
    required int uploadLimitBps,
  }) async {}

  @override
  Future<List<EngineStatus>> allStatus() async => const [];

  @override
  Future<EngineStatus?> status(String infoHash) async => null;

  @override
  Future<void> addTracker(String infoHash, String announceUrl) async {}

  @override
  Future<List<String>> trackers(String infoHash) async => const [];
}
