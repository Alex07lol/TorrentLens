import '../../integrations/torrent/torrent_engine.dart';

/// Identifies a partially-downloaded file the player may read while the engine
/// keeps fetching it.
class StreamingTarget {
  final String infoHash;

  /// Sanitized path relative to the download directory. The engine resolves this
  /// to its own file index; it is the only stable key for a file.
  final String relativePath;

  /// Absolute path of the (possibly sparse, possibly incomplete) local file.
  final String localPath;

  /// Advertised length of the file, from the torrent's metadata.
  final int fileLengthBytes;

  final String title;

  const StreamingTarget({
    required this.infoHash,
    required this.relativePath,
    required this.localPath,
    required this.fileLengthBytes,
    required this.title,
  });
}

/// Where a play-while-downloading session currently stands.
enum StreamingPhase {
  /// The engine has not finished fetching the torrent's metadata; there is
  /// nothing to prioritise yet.
  resolvingMetadata,

  /// The prioritised window is not deep enough to start (or keep) playing.
  buffering,

  /// Enough contiguous data is on disk ahead of the playhead.
  ready,

  /// The buffer is not growing: no peers, no speed, or a stalled tracker.
  stalled,

  /// The whole file is on disk, so playback no longer needs the engine.
  complete,

  /// The engine, the torrent, or the source itself is unusable.
  failed,
}

/// The byte window the player wants next, expressed both in torrent bytes and in
/// absolute piece indices so the engine can act on it.
class PieceWindow {
  /// Absolute torrent byte offset where the window starts (the playhead).
  final int startByteInTorrent;

  /// Absolute torrent byte offset one past the end of the window.
  final int endByteInTorrent;

  /// Playhead relative to the start of the file, in bytes.
  final int startByteInFile;

  /// Bytes of the window that actually exist (clamped to the end of the file).
  final int windowBytes;

  final int firstPiece;
  final int lastPiece;

  const PieceWindow({
    required this.startByteInTorrent,
    required this.endByteInTorrent,
    required this.startByteInFile,
    required this.windowBytes,
    required this.firstPiece,
    required this.lastPiece,
  });

  int get pieceCount => lastPiece - firstPiece + 1;

  /// True when the playhead sits inside the first piece rather than at its
  /// start, which is what makes an exact buffer count one piece harder.
  bool isPlayheadMidPiece(int pieceLength) =>
      pieceLength > 0 && startByteInTorrent % pieceLength != 0;
}

/// How a partially-downloaded file is turned into playback.
///
/// Everything here is arithmetic over numbers the engine measured: no platform
/// calls, no clock, no I/O. That keeps the risky part of streaming (piece
/// boundaries, buffer depth, when to slide the window) unit-testable on the
/// host, and leaves the native side responsible only for libtorrent calls.
class StreamingPolicy {
  /// The default read-ahead window, exposed so the UI can show the same number
  /// it is actually using.
  static const int defaultReadAheadBytes = 24 * 1024 * 1024;

  /// Bytes from the end of the file to prioritise when the player cannot read the
  /// container index. MP4 keeps `moov` at the end unless the file was written
  /// for streaming, so this is what lets such files start before they finish.
  static const int headerTailBytes = 4 * 1024 * 1024;

  /// How far ahead of the playhead to keep prioritised.
  final int readAheadBytes;

  /// Never start playback with less than this much contiguous data, even when
  /// the read-ahead window is small.
  final int minBufferBytes;

  /// Upper bound on pieces per window, matching the native clamp in
  /// `StreamQuery.MAX_RANGE_PIECES`.
  final int maxWindowPieces;

  /// Deadline for the piece under the playhead, in milliseconds. libtorrent
  /// treats deadlines as relative durations from now.
  final int deadlineMs;

  /// Added per piece of distance from the playhead, so the window downloads in
  /// playback order instead of racing.
  final int deadlineStepMs;

  /// How often the session re-reads the engine while waiting for data.
  final Duration pollInterval;

  /// How long the buffer may stay flat before the session calls it stalled.
  final Duration stallAfter;

  const StreamingPolicy({
    this.readAheadBytes = defaultReadAheadBytes,
    this.minBufferBytes = 4 * 1024 * 1024,
    this.maxWindowPieces = 512,
    this.deadlineMs = 1500,
    this.deadlineStepMs = 250,
    this.pollInterval = const Duration(milliseconds: 700),
    this.stallAfter = const Duration(seconds: 10),
  });

  /// The piece window covering the read-ahead starting at [startByteInFile].
  ///
  /// [startByteInFile] is clamped into the file, and the window is clamped to
  /// the file's own piece range so a window never asks the engine about pieces
  /// that belong to another file of the same torrent.
  PieceWindow windowFor(StreamSnapshot snapshot, int startByteInFile) {
    final pieceLength = snapshot.pieceLength > 0 ? snapshot.pieceLength : 1;
    final fileLength = snapshot.fileLengthBytes;

    final clampedStart = fileLength <= 0
        ? 0
        : startByteInFile.clamp(0, fileLength - 1);
    final startInTorrent = snapshot.fileOffsetInTorrent + clampedStart;
    final windowBytes = fileLength <= 0
        ? 0
        : (fileLength - clampedStart).clamp(0, readAheadBytes);
    final endInTorrent = startInTorrent + windowBytes;

    final firstPiece = startInTorrent ~/ pieceLength;
    // An empty window still names the piece at the playhead, so the engine has
    // something concrete to prioritise.
    final lastByte = endInTorrent > startInTorrent ? endInTorrent - 1 : startInTorrent;
    final lastPiece = lastByte ~/ pieceLength;

    final boundedFirst =
        firstPiece.clamp(snapshot.firstFilePiece, snapshot.lastFilePiece);
    final boundedLast = lastPiece
        .clamp(boundedFirst, snapshot.lastFilePiece)
        .clamp(boundedFirst, boundedFirst + maxWindowPieces - 1);

    return PieceWindow(
      startByteInTorrent: startInTorrent,
      endByteInTorrent: endInTorrent,
      startByteInFile: clampedStart,
      windowBytes: windowBytes,
      firstPiece: boundedFirst,
      lastPiece: boundedLast,
    );
  }

  /// Contiguous bytes available from the window's start, in torrent space,
  /// clamped to the window itself.
  ///
  /// Contiguity is what matters for playback: a torrent that has 90% of a file
  /// scattered across it can still be unplayable at the playhead.
  int contiguousBytes({
    required PieceWindow window,
    required Set<int> have,
    required int pieceLength,
    required int windowStartByteInTorrent,
  }) {
    if (pieceLength <= 0 || window.windowBytes <= 0) return 0;
    var consecutive = 0;
    for (var piece = window.firstPiece; piece <= window.lastPiece; piece++) {
      if (!have.contains(piece)) break;
      consecutive++;
    }
    if (consecutive == 0) return 0;
    // The first piece can start before the playhead, so subtract the part of it
    // that lies behind us. Without this the reported buffer would over-count by
    // up to one piece.
    final alignedStart = window.firstPiece * pieceLength;
    final offsetIntoFirstPiece = (windowStartByteInTorrent - alignedStart).clamp(0, pieceLength);
    final bytes = consecutive * pieceLength - offsetIntoFirstPiece;
    return bytes.clamp(0, window.windowBytes);
  }

  /// Contiguous bytes required before playback may start (or resume).
  ///
  /// A quarter of the read-ahead window, floored at [minBufferBytes], and never
  /// more than the file has left to give.
  int requiredBufferBytes({required int fileLengthBytes, required int startByteInFile}) {
    final remaining = (fileLengthBytes - startByteInFile).clamp(0, fileLengthBytes);
    final target = readAheadBytes ~/ 4 > minBufferBytes ? readAheadBytes ~/ 4 : minBufferBytes;
    return remaining < target ? remaining : target;
  }

  /// Turns measurements into the state the UI shows.
  ///
  /// [sinceProgress] is how long the buffered byte count has been unchanged.
  StreamingPlaybackState evaluate({
    required StreamSnapshot snapshot,
    required PieceWindow window,
    required int contiguousBytes,
    Duration sinceProgress = Duration.zero,
  }) {
    final required = snapshot.fileComplete
        ? 0
        : requiredBufferBytes(
            fileLengthBytes: snapshot.fileLengthBytes,
            startByteInFile: window.startByteInFile,
          );
    final percent = required == 0
        ? 1.0
        : (contiguousBytes / required).clamp(0.0, 1.0).toDouble();

    StreamingPhase phase;
    if (snapshot.state == 'resolvingMetadata') {
      phase = StreamingPhase.resolvingMetadata;
    } else if (snapshot.state == 'unavailable' || snapshot.state == 'failed') {
      phase = StreamingPhase.failed;
    } else if (snapshot.fileComplete) {
      phase = StreamingPhase.complete;
    } else if (contiguousBytes >= required) {
      phase = StreamingPhase.ready;
    } else if (sinceProgress >= stallAfter) {
      phase = StreamingPhase.stalled;
    } else {
      phase = StreamingPhase.buffering;
    }

    return StreamingPlaybackState(
      phase: phase,
      bufferedBytes: contiguousBytes,
      requiredBytes: required,
      bufferPercent: percent,
      downloadedBytes: snapshot.fileDoneBytes,
      totalBytes: snapshot.fileLengthBytes,
      downloadBps: snapshot.downloadBps,
      numPeers: snapshot.numPeers,
      numSeeds: snapshot.numSeeds,
      fileComplete: snapshot.fileComplete,
      message: _messageFor(phase, snapshot, contiguousBytes, required),
    );
  }

  /// True when the window must be re-applied because the playhead moved far
  /// enough that the prioritised pieces no longer cover it.
  ///
  /// Re-applying on every poll would keep resetting piece deadlines, so the
  /// window only slides once the playhead has consumed half of it.
  bool shouldReprioritise({
    required int lastPrioritisedStartByte,
    required int newStartByte,
  }) {
    if (newStartByte < lastPrioritisedStartByte) return true;
    return newStartByte - lastPrioritisedStartByte >= readAheadBytes ~/ 2;
  }

  /// Byte offset to prioritise for a playback position, or null when it cannot
  /// be known.
  ///
  /// This assumes a roughly constant bitrate: the media duration is spread
  /// evenly across the file size. For variable-bitrate media the estimate can be
  /// off, which is why the buffer is measured from the resulting window rather
  /// than trusted blindly.
  int? byteOffsetForPosition({
    required Duration position,
    required Duration duration,
    required int fileLengthBytes,
  }) {
    if (duration.inMilliseconds <= 0 || fileLengthBytes <= 0) return null;
    final fraction = (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final offset = (fraction * fileLengthBytes).floor();
    return offset.clamp(0, fileLengthBytes - 1);
  }

  String _messageFor(
    StreamingPhase phase,
    StreamSnapshot snapshot,
    int buffered,
    int required,
  ) {
    switch (phase) {
      case StreamingPhase.resolvingMetadata:
        return 'Fetching torrent metadata from peers before playback can start.';
      case StreamingPhase.buffering:
        return 'Buffering from peers — ${_mib(buffered)} MiB of ${_mib(required)} MiB ready.';
      case StreamingPhase.ready:
        return 'Enough data buffered ahead of the playhead.';
      case StreamingPhase.stalled:
        return 'The buffer is not growing: '
            '${snapshot.numPeers} peer(s) connected, ${_rate(snapshot.downloadBps)}. '
            'Playback will resume if data arrives.';
      case StreamingPhase.complete:
        return 'Fully downloaded — playing from disk, no peers needed.';
      case StreamingPhase.failed:
        return 'The torrent is not available for streaming (state: ${snapshot.state}).';
    }
  }

  static String _mib(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
  static String _rate(int bytesPerSecond) => bytesPerSecond <= 0
      ? 'no download speed'
      : '${(bytesPerSecond / 1024).toStringAsFixed(0)} KiB/s';
}

/// The state a play-while-downloading session is in, ready for display.
class StreamingPlaybackState {
  final StreamingPhase phase;
  final int bufferedBytes;
  final int requiredBytes;
  final double bufferPercent;
  final int downloadedBytes;
  final int totalBytes;
  final int downloadBps;
  final int numPeers;
  final int numSeeds;
  final bool fileComplete;
  final String message;

  const StreamingPlaybackState({
    required this.phase,
    required this.bufferedBytes,
    required this.requiredBytes,
    required this.bufferPercent,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.downloadBps,
    required this.numPeers,
    required this.numSeeds,
    required this.fileComplete,
    required this.message,
  });

  /// Playback may run (continue) in this phase.
  bool get canPlay =>
      phase == StreamingPhase.ready || phase == StreamingPhase.complete;

  /// The session is over: the window can be released.
  bool get isFinished =>
      phase == StreamingPhase.complete || phase == StreamingPhase.failed;

  static const StreamingPlaybackState initial = StreamingPlaybackState(
    phase: StreamingPhase.resolvingMetadata,
    bufferedBytes: 0,
    requiredBytes: 0,
    bufferPercent: 0,
    downloadedBytes: 0,
    totalBytes: 0,
    downloadBps: 0,
    numPeers: 0,
    numSeeds: 0,
    fileComplete: false,
    message: 'Preparing streaming session…',
  );
}
