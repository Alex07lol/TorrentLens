import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/torrent/streaming.dart';
import '../../integrations/torrent/torrent_engine.dart';

/// Runs one play-while-downloading session.
///
/// The controller owns the read-ahead window: it tells the native engine which
/// pieces to fetch first, measures what is actually on disk, and reports the
/// buffering state. It never plays anything itself — the player reads the local
/// partial file, and this class decides when that is safe.
///
/// Everything time-dependent is injectable ([now], [policy], [autoPoll]) so a
/// whole session can be driven deterministically from a test.
class StreamingPlaybackController extends ChangeNotifier {
  final TorrentEngine engine;
  final StreamingTarget target;
  final StreamingPolicy policy;

  /// Starts the polling timer. Tests drive [poll] themselves and pass false.
  final bool autoPoll;

  final DateTime Function() now;

  Timer? _timer;
  bool _disposed = false;
  bool _busy = false;
  bool _streamReleased = false;
  StreamSnapshot? _snapshot;
  PieceWindow? _window;
  int _lastPrioritisedStartByte = -1;
  int _lastBufferedBytes = -1;
  DateTime? _lastProgressAt;
  StreamingPlaybackState _state = StreamingPlaybackState.initial;

  StreamingPlaybackController({
    required this.engine,
    required this.target,
    this.policy = const StreamingPolicy(),
    this.autoPoll = true,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  StreamingPlaybackState get state => _state;
  StreamSnapshot? get snapshot => _snapshot;
  PieceWindow? get window => _window;
  bool get isPolling => _timer != null;
  bool get isDisposed => _disposed;

  /// Absolute byte offset the engine is currently prioritising, or -1 before the
  /// first window is applied.
  int get prioritisedStartByte => _lastPrioritisedStartByte;

  /// Opens the window at the start of the file and starts measuring.
  Future<void> start() async {
    await _openWindow(0);
    if (_disposed) return;
    // Not when the very first snapshot already finished the session: a completed
    // or failed stream has nothing left to poll for.
    if (autoPoll && _timer == null && !_state.isFinished) {
      _timer = Timer.periodic(policy.pollInterval, (_) => poll());
    }
  }

  /// Tells the session where playback is, so the window can follow it.
  ///
  /// Called on every position update; the window only moves once the playhead
  /// has consumed half of it, so this is cheap and never resets piece deadlines
  /// without reason.
  void followPosition(Duration position, Duration duration) {
    if (_disposed || _state.phase == StreamingPhase.complete) return;
    final offset = policy.byteOffsetForPosition(
      position: position,
      duration: duration,
      fileLengthBytes: target.fileLengthBytes,
    );
    if (offset == null) return;
    final last = _lastPrioritisedStartByte;
    if (last >= 0 &&
        !policy.shouldReprioritise(lastPrioritisedStartByte: last, newStartByte: offset)) {
      return;
    }
    unawaited(_openWindow(offset));
  }

  /// Re-opens the window at an absolute byte offset in the file.
  ///
  /// Used for the tail of a file, where a container index may live, and as the
  /// fallback when a playback position cannot be mapped to bytes.
  void anchorAtByte(int byteOffset) {
    if (_disposed || _streamReleased) return;
    final last = target.fileLengthBytes > 0 ? target.fileLengthBytes - 1 : 0;
    unawaited(_openWindow(byteOffset.clamp(0, last)));
  }

  /// Re-opens the window for a playback position.
  ///
  /// Returns false when the position cannot be mapped to a byte offset, which
  /// happens while the duration is still unknown. The caller is expected to say
  /// so instead of guessing a window.
  bool anchorAtPosition(Duration position, Duration duration) {
    if (_disposed || _streamReleased) return false;
    final offset = policy.byteOffsetForPosition(
      position: position,
      duration: duration,
      fileLengthBytes: target.fileLengthBytes,
    );
    if (offset == null) return false;
    unawaited(_openWindow(offset));
    return true;
  }

  /// Re-reads the engine and updates the buffering state.
  ///
  /// Public so tests (and the UI) can advance a session without waiting on
  /// wall-clock timers.
  Future<void> poll() async {
    if (_disposed || _busy) return;
    final win = _window;
    final snap = _snapshot;
    if (win == null || snap == null) return;
    if (_state.phase == StreamingPhase.failed || _state.phase == StreamingPhase.complete) return;
    _busy = true;
    try {
      final fresh = await engine.streamSnapshot(
        target.infoHash,
        target.relativePath,
        firstPiece: win.firstPiece,
        lastPiece: win.lastPiece,
      );
      _applySnapshot(fresh, reprioritised: false, startByteInFile: win.startByteInFile);
    } catch (e) {
      _fail(e);
    } finally {
      _busy = false;
    }
  }

  /// Releases the window and restores the user's file selection.
  Future<void> end() async {
    _timer?.cancel();
    _timer = null;
    if (_streamReleased) return;
    _streamReleased = true;
    try {
      await engine.endStreaming(target.infoHash, target.relativePath);
    } catch (_) {
      // Releasing priorities is best-effort: the engine may already be gone, and
      // a failure here does not affect the user's data.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    if (!_streamReleased) {
      _streamReleased = true;
      unawaited(engine.endStreaming(target.infoHash, target.relativePath).catchError((_) {}));
    }
    super.dispose();
  }

  /// Applies the read-ahead window over [byteOffset] to the native engine.
  ///
  /// Only called when the window actually needs to move (session start, or the
  /// playhead consumed half of the previous window), so piece deadlines are not
  /// reset on every poll.
  Future<void> _openWindow(int byteOffset) async {
    if (_disposed || _streamReleased) return;
    try {
      // The piece geometry is itself only known from a snapshot, so probe once
      // before the first window can be computed.
      final probe = _snapshot ??
          await engine.streamSnapshot(target.infoHash, target.relativePath, firstPiece: 0, lastPiece: 0);
      final request = policy.windowFor(probe, byteOffset);
      final fresh = await engine.beginStreaming(
        target.infoHash,
        target.relativePath,
        firstPiece: request.firstPiece,
        lastPiece: request.lastPiece,
        deadlineMs: policy.deadlineMs,
        stepMs: policy.deadlineStepMs,
      );
      _lastPrioritisedStartByte = request.startByteInFile;
      _applySnapshot(fresh, reprioritised: true, startByteInFile: request.startByteInFile);
    } catch (e) {
      _fail(e);
    }
  }

  /// [startByteInFile] is the playhead the window was aimed at. It must be
  /// passed in rather than read back from `_window`, because a seek replaces the
  /// playhead before the new measurements arrive.
  void _applySnapshot(
    StreamSnapshot fresh, {
    required bool reprioritised,
    required int startByteInFile,
  }) {
    if (_disposed) return;
    _snapshot = fresh;

    // Measure only over the pieces the engine actually reported: it clamps
    // ranges, and a piece it never named cannot be assumed available. The byte
    // bounds come from the playhead, which is what the buffer target is about.
    final pieceWindow = policy.windowFor(fresh, startByteInFile);
    final lastPiece = fresh.rangeLastPiece >= fresh.rangeFirstPiece
        ? fresh.rangeLastPiece
        : fresh.rangeFirstPiece;
    final measured = PieceWindow(
      startByteInTorrent: pieceWindow.startByteInTorrent,
      endByteInTorrent: pieceWindow.endByteInTorrent,
      startByteInFile: pieceWindow.startByteInFile,
      windowBytes: pieceWindow.windowBytes,
      firstPiece: fresh.rangeFirstPiece,
      lastPiece: lastPiece,
    );

    final pieceLength = fresh.pieceLength > 0 ? fresh.pieceLength : 1;
    final contiguous = policy.contiguousBytes(
      window: measured,
      have: fresh.piecesHaveSet,
      pieceLength: pieceLength,
      windowStartByteInTorrent: measured.firstPiece * pieceLength,
    );

    final timestamp = now();
    if (reprioritised || contiguous != _lastBufferedBytes) {
      _lastProgressAt = timestamp;
    }
    _lastBufferedBytes = contiguous;
    final sinceProgress =
        _lastProgressAt == null ? Duration.zero : timestamp.difference(_lastProgressAt!);

    _window = measured;
    final next = policy.evaluate(
      snapshot: fresh,
      window: measured,
      contiguousBytes: contiguous,
      sinceProgress: sinceProgress,
    );

    if (next.phase == StreamingPhase.complete && !_streamReleased) {
      // Nothing left to fetch: hand the file's priority back to the user's
      // selection so the rest of the torrent is not held at top priority.
      unawaited(end());
    }
    _emit(next);
  }

  void _fail(Object error) {
    _timer?.cancel();
    _timer = null;
    final message = error is TorrentEngineException
        ? error.message
        : 'The torrent engine reported: $error';
    _emit(StreamingPlaybackState(
      phase: StreamingPhase.failed,
      bufferedBytes: 0,
      requiredBytes: 0,
      bufferPercent: 0,
      downloadedBytes: _snapshot?.fileDoneBytes ?? 0,
      totalBytes: target.fileLengthBytes,
      downloadBps: 0,
      numPeers: 0,
      numSeeds: 0,
      fileComplete: false,
      message: message,
    ));
  }

  void _emit(StreamingPlaybackState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }
}
