import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../app/providers.dart';
import '../../design_system/components.dart';
import '../../domain/media/subtitles.dart';
import '../../domain/models/progress.dart';
import '../../domain/torrent/streaming.dart';
import '../../integrations/media_resolver/playback_diagnostics.dart';
import '../../navigation/route_args.dart';
import '../../util/format.dart';
import 'streaming_playback_controller.dart';

/// Media player built on Media3/ExoPlayer through `video_player`.
///
/// Two modes:
///  * A finished local file or a network URL, played directly.
///  * A torrent-backed file ([PlayerArgs.stream]): the player reads the local
///    *partial* file, while [StreamingPlaybackController] tells the engine which
///    pieces to fetch for the playhead. Playback only starts once enough
///    contiguous data is on disk, a seek re-aims the window, and a player that
///    reads past the downloaded region is treated as "buffer ran dry" rather
///    than as a fatal error.
///
/// Honest scope: media_player exposes playback, seeking, speed, and position
/// persistence. Android's player does not expose per-track audio selection
/// through this plugin, so that is reported as a limitation rather than faked.
/// External subtitles *are* supported, by parsing SRT/VTT and rendering the
/// active cue as an overlay.
class PlayerScreen extends ConsumerStatefulWidget {
  final PlayerArgs args;
  const PlayerScreen({super.key, required this.args});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  /// Retries allowed after the player reads past the downloaded region.
  static const int _maxStarvationRetries = 5;

  VideoPlayerController? _controller;
  StreamingPlaybackController? _stream;
  SubtitleTrack? _subtitles;
  String? _subtitleLabel;
  SubtitleCue? _activeCue;
  Timer? _cueTimer;
  double _speed = 1.0;
  bool _showControls = true;
  PlaybackDiagnostics? _diagnostics;
  String? _error;
  bool _initialising = true;
  bool _loadingPlayer = false;
  bool _triedHeaderHint = false;
  int _starvationRetries = 0;
  Duration _lastPosition = Duration.zero;
  Duration _lastDuration = Duration.zero;
  int _lastRenderedSecond = -1;

  @override
  void initState() {
    super.initState();
    final target = widget.args.stream;
    if (target == null) {
      _init();
    } else {
      _initStreaming(target);
    }
  }

  @override
  void dispose() {
    _cueTimer?.cancel();
    _stream?.removeListener(_onStreamChanged);
    _stream?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  String get _contentId => widget.args.contentId ?? widget.args.source;

  bool get _isStreaming => widget.args.stream != null;
  StreamingPlaybackState? get _streamState => _stream?.state;

  /// True while the session is waiting for the engine to deliver data.
  bool get _awaitingBuffer {
    final s = _streamState;
    return _isStreaming && s != null && !s.canPlay && s.phase != StreamingPhase.failed;
  }

  // ---------------------------------------------------------------- streaming

  Future<void> _initStreaming(StreamingTarget target) async {
    final session = StreamingPlaybackController(
      engine: ref.read(servicesProvider).engine,
      target: target,
    );
    _stream = session;
    session.addListener(_onStreamChanged);
    await session.start();
    if (!mounted) return;
    _onStreamChanged();
  }

  void _onStreamChanged() {
    final session = _stream;
    if (session == null || !mounted) return;
    final state = session.state;
    if (state.phase == StreamingPhase.failed) {
      setState(() {
        _error = state.message;
        _initialising = false;
      });
      return;
    }
    if (state.canPlay && _controller == null && !_loadingPlayer) {
      unawaited(_startBufferedPlayer());
      return;
    }
    // Buffer ran dry (a seek ahead of the window, or a slow peer set): stop the
    // player instead of letting it decode whatever the sparse file returns.
    final controller = _controller;
    if (!state.canPlay && controller != null) {
      if (controller.value.isPlaying) unawaited(controller.pause());
    }
    setState(() {});
  }

  /// Opens the local partial file once the session says it can be read.
  Future<void> _startBufferedPlayer() async {
    final target = widget.args.stream;
    if (target == null || _loadingPlayer) return;
    _loadingPlayer = true;
    // A retry resumes exactly where the player died; a first start restores the
    // position saved by a previous session instead.
    final resumeAtMs = _restoreAtMs;
    try {
      final file = File(target.localPath);
      if (!file.existsSync()) {
        throw StateError('The partial file does not exist yet at ${target.localPath}');
      }
      final controller = VideoPlayerController.file(file);
      _controller = controller;
      await controller.initialize();
      await controller.setPlaybackSpeed(_speed);
      if (resumeAtMs > 0) {
        await controller.seekTo(Duration(milliseconds: resumeAtMs));
      } else {
        await _restorePosition();
      }
      _restoreAtMs = 0;
      await _loadSubtitle();
      controller.addListener(_onTick);
      await controller.play();
      if (!mounted) return;
      setState(() => _initialising = false);
      _ensureCueTimer();
    } catch (e) {
      _controller?.dispose();
      _controller = null;
      if (!mounted) return;
      _handleStreamStarvation('$e');
    } finally {
      _loadingPlayer = false;
    }
  }

  int _restoreAtMs = 0;

  /// The player could not read what it needed (usually: it read past the
  /// downloaded region, or the container index is not on disk yet).
  ///
  /// Recovery is real work, not a retry loop for show: the first attempt asks
  /// the engine for the *end* of the file, where MP4 `moov` indexes usually
  /// live, and later attempts re-aim the window at the playhead.
  void _handleStreamStarvation(String detail) {
    final target = widget.args.stream;
    if (target == null) return;
    if (_starvationRetries >= _maxStarvationRetries) {
      setState(() {
        _initialising = false;
        _error = 'Playback kept running ahead of the download, so it was stopped '
            'after $_maxStarvationRetries attempts. You can keep downloading and '
            'try again, or wait for the file to finish.';
        _diagnostics = PlaybackDiagnostics(
          source: Uri.file(target.localPath),
          failureKind: PlaybackFailureKind.decodeError,
          rawMessage: detail,
        );
      });
      return;
    }
    _starvationRetries++;
    _restoreAtMs = _lastPosition.inMilliseconds;
    final length = target.fileLengthBytes;
    final tailStart = length - StreamingPolicy.headerTailBytes;
    final useHeaderHint = !_triedHeaderHint && length > StreamingPolicy.headerTailBytes;
    _triedHeaderHint = true;
    if (useHeaderHint) {
      _stream?.anchorAtByte(tailStart);
    } else {
      final ok = _stream?.anchorAtPosition(_lastPosition, _lastDuration) ?? false;
      if (!ok) _stream?.anchorAtByte(0);
    }
    if (!mounted) return;
    setState(() {
      _initialising = false;
      _error = null;
    });
  }

  /// Re-anchors the read-ahead window after a seek the policy cannot infer.
  void _onSeek(Duration position) {
    final session = _stream;
    final controller = _controller;
    if (session == null || controller == null) return;
    final duration = controller.value.duration;
    if (!session.anchorAtPosition(position, duration)) {
      // Without a duration the position cannot be mapped to bytes; say so rather
      // than guessing a window.
      _snack('The media duration is unknown, so the read-ahead window cannot be re-aimed yet.');
    }
  }

  // ---------------------------------------------------------------- direct play

  Future<void> _init() async {
    try {
      final controller = widget.args.isLocalFile
          ? VideoPlayerController.file(File(widget.args.source))
          : VideoPlayerController.networkUrl(Uri.parse(widget.args.source));
      _controller = controller;
      await controller.initialize();
      await _restorePosition();
      await controller.play();
      controller.addListener(_onTick);
      await _loadSubtitle();
      if (!mounted) return;
      setState(() => _initialising = false);
      _ensureCueTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialising = false;
        _error = '$e';
        _diagnostics = PlaybackDiagnostics(
          source: Uri.tryParse(widget.args.source),
          mimeType: widget.args.mimeType,
          failureKind: PlaybackFailureKind.unknown,
          rawMessage: '$e',
        );
      });
    }
  }

  void _onTick() {
    final value = _controller?.value;
    if (value == null) return;
    if (value.hasError) {
      if (_isStreaming) {
        if (_loadingPlayer) return;
        final controller = _controller;
        _controller = null;
        controller?.removeListener(_onTick);
        controller?.dispose();
        _handleStreamStarvation(value.errorDescription ?? 'the player reported an error');
      } else if (_error == null) {
        setState(() {
          _error = value.errorDescription;
          _diagnostics = PlaybackDiagnostics(
            source: Uri.tryParse(widget.args.source),
            failureKind: PlaybackFailureKind.decodeError,
            rawMessage: value.errorDescription,
          );
        });
      }
      return;
    }
    if (!value.isInitialized) return;
    _lastPosition = value.position;
    _lastDuration = value.duration;
    _stream?.followPosition(value.position, value.duration);
    if (!mounted) return;
    // Repaint only when the displayed second changes: the player ticks several
    // times a second and rebuilding the whole screen that often is waste.
    if (value.position.inSeconds != _lastRenderedSecond) {
      _lastRenderedSecond = value.position.inSeconds;
      setState(() {});
    }
  }

  void _ensureCueTimer() {
    _cueTimer ??= Timer.periodic(const Duration(milliseconds: 250), (_) => _updateCue());
  }

  Future<void> _restorePosition() async {
    final saved = await ref.read(servicesProvider).progress.playbackPosition(_contentId);
    if (saved == null || saved.positionMs <= 0) return;
    final total = _controller!.value.duration.inMilliseconds;
    // Ignore near-finished positions so replaying starts from the beginning.
    if (total > 0 && saved.positionMs > total - 5000) return;
    await _controller!.seekTo(Duration(milliseconds: saved.positionMs));
  }

  Future<void> _savePosition() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    await ref.read(servicesProvider).progress.savePlaybackPosition(PlaybackPosition(
          contentId: _contentId,
          positionMs: c.value.position.inMilliseconds,
          durationMs: c.value.duration.inMilliseconds,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ));
  }

  Future<void> _loadSubtitle() async {
    // Look for a sibling subtitle file with the same base name.
    final source = widget.args.stream?.localPath ?? widget.args.source;
    if (!widget.args.isLocalFile && !_isStreaming) return;
    final base = source.substring(0, source.lastIndexOf('.'));
    for (final ext in const ['.srt', '.vtt']) {
      final candidate = '$base$ext';
      if (File(candidate).existsSync()) {
        final content = await File(candidate).readAsString();
        if (!mounted) return;
        setState(() {
          _subtitles = SubtitleTrack.parse(content, formatHint: ext.substring(1));
          _subtitleLabel = candidate.split('/').last;
        });
        return;
      }
    }
  }

  void _updateCue() {
    final track = _subtitles;
    final c = _controller;
    if (track == null || c == null) return;
    final cue = track.cueAt(c.value.position.inMilliseconds);
    if (cue?.text != _activeCue?.text) {
      setState(() => _activeCue = cue);
    }
  }

  // ---------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.args.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Media source details',
            onPressed: _showDetails,
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: _error != null
          ? _errorView()
          : _initialising
              ? LoadingView(label: _streamMessage ?? 'Preparing playback…')
              : c == null || !c.value.isInitialized
                  ? (_isStreaming ? _bufferView() : const LoadingView(label: 'Preparing playback…'))
                  : Stack(
                      children: [
                        Center(
                          child: GestureDetector(
                            onTap: () => setState(() => _showControls = !_showControls),
                            child: AspectRatio(
                              aspectRatio:
                                  c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                              child: Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  VideoPlayer(c),
                                  if (_activeCue != null)
                                    Positioned(
                                      bottom: 64,
                                      left: 12,
                                      right: 12,
                                      child: Text(
                                        _activeCue!.text,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          height: 1.3,
                                          shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                                        ),
                                      ),
                                    ),
                                  if (_showControls) _controls(c),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_awaitingBuffer)
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 12,
                            child: _bufferBadge(),
                          ),
                      ],
                    ),
    );
  }

  String? get _streamMessage => _streamState?.message;

  /// Shown before the first frame is available: the session is buffering.
  Widget _bufferView() {
    final s = _streamState ?? StreamingPlaybackState.initial;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.downloading_outlined, color: Colors.white70, size: 48),
          const SizedBox(height: 16),
          Text(s.message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: s.requiredBytes == 0 ? null : s.bufferPercent),
          const SizedBox(height: 8),
          Text(
            _bufferStats(s),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Playback starts once enough data ahead of the playhead is on disk. '
            'Seeking re-prioritises the pieces you jump to.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _bufferStats(StreamingPlaybackState s) {
    final total = widget.args.stream?.fileLengthBytes ?? s.totalBytes;
    final percent = total == 0 ? '—' : Fmt.percent(s.downloadedBytes / total);
    return 'Buffered ${Fmt.bytes(s.bufferedBytes)} of ${Fmt.bytes(s.requiredBytes)} needed · '
        '↓${Fmt.speed(s.downloadBps)} · ${s.numPeers} peer(s) · '
        'file $percent downloaded';
  }

  Widget _bufferBadge() {
    final s = _streamState ?? StreamingPlaybackState.initial;
    return Container(
      key: const Key('stream-buffer-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              s.message,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(s.bufferPercent * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _errorView() {
    final d = _diagnostics;
    final s = _streamState;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 48),
          const SizedBox(height: 16),
          Text(d?.explanation ?? _error!, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 12),
          Text('Source: ${d?.sourceLabel ?? widget.args.source}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          if (s != null) ...[
            const SizedBox(height: 8),
            Text('Torrent file: ${_fmtDur(_lastPosition)} buffered, '
                '${Fmt.bytes(s.bufferedBytes)} of ${Fmt.bytes(s.requiredBytes)} ready',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
          const SizedBox(height: 20),
          FilledButton.tonal(
            onPressed: () {
              setState(() {
                _error = null;
                _diagnostics = null;
                _initialising = true;
                _starvationRetries = 0;
              });
              if (_isStreaming) {
                unawaited(_initStreaming(widget.args.stream!));
              } else {
                _init();
              }
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _controls(VideoPlayerController c) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black54]),
      ),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.symmetric(horizontal: 12)),
          Row(
            children: [
              IconButton(
                color: Colors.white,
                icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
              ),
              if (_isStreaming) ...[
                IconButton(
                  tooltip: 'Back 10 seconds',
                  color: Colors.white,
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => _seekBy(c, const Duration(seconds: -10)),
                ),
                IconButton(
                  tooltip: 'Forward 30 seconds',
                  color: Colors.white,
                  icon: const Icon(Icons.forward_30),
                  onPressed: () => _seekBy(c, const Duration(seconds: 30)),
                ),
              ],
              Text(
                '${_fmtDur(c.value.position)} / ${_fmtDur(c.value.duration)}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const Spacer(),
              PopupMenuButton<double>(
                tooltip: 'Playback speed',
                initialValue: _speed,
                onSelected: (v) {
                  setState(() => _speed = v);
                  c.setPlaybackSpeed(v);
                },
                itemBuilder: (_) => [
                  for (final s in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                    PopupMenuItem(value: s, child: Text('${s}x')),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('${_speed}x', style: const TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Seeks and re-aims the read-ahead window at the destination.
  Future<void> _seekBy(VideoPlayerController c, Duration delta) async {
    final target = c.value.position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (c.value.duration > Duration.zero && target > c.value.duration ? c.value.duration : target);
    await c.seekTo(clamped);
    _onSeek(clamped);
    if (!c.value.isPlaying) await c.play();
  }

  static String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> _showDetails() async {
    await _savePosition();
    final c = _controller;
    final s = _streamState;
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Media source', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_isStreaming) ...[
              _kv('Mode', 'Play while downloading (torrent)'),
              _kv('File', widget.args.stream!.relativePath),
              _kv('Read-ahead', Fmt.bytes(const StreamingPolicy().readAheadBytes)),
              _kv('Buffered ahead', Fmt.bytes(s?.bufferedBytes ?? 0)),
              _kv('Needed ahead', Fmt.bytes(s?.requiredBytes ?? 0)),
              _kv('Peers', '${s?.numPeers ?? 0} · ${s?.numSeeds ?? 0} seed(s)'),
              _kv('Phase', s?.phase.name ?? '—'),
            ] else ...[
              _kv('Mode', widget.args.isLocalFile ? 'Local file' : 'Network stream'),
              _kv('Source', (c == null ? widget.args.source : '${Uri.tryParse(widget.args.source)?.scheme}://…')),
            ],
            _kv('MIME type', widget.args.mimeType ?? 'unknown'),
            _kv('Duration', c == null ? '—' : _fmtDur(c.value.duration)),
            _kv('Size', c == null ? '—' : '${c.value.size.width.toInt()}×${c.value.size.height.toInt()}'),
            _kv('Subtitle', _subtitleLabel ?? 'none attached'),
            const SizedBox(height: 12),
            Text(
              _isStreaming
                  ? 'The player reads the partially downloaded file directly; the torrent '
                      'engine prioritises the pieces ahead of the playhead. Variable-bitrate '
                      'media is positioned approximately, and a seek may need to buffer again.'
                  : 'Audio-track selection is not exposed by the Android player plugin used '
                      'here, so it is not offered rather than faked. Subtitle tracks are attached '
                      'from files next to the video.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 110, child: Text(k, style: Theme.of(context).textTheme.bodySmall)),
            Expanded(child: Text(v)),
          ],
        ),
      );

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Kept for the diagnostics panel; formats a byte count consistently.
String formatBytesForPlayer(int v) => Fmt.bytes(v);
