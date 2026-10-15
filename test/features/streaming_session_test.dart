import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/domain/torrent/streaming.dart';
import 'package:torrentlens/features/player/streaming_playback_controller.dart';
import 'package:torrentlens/integrations/torrent/torrent_engine.dart';

import '../support/fake_torrent_engine.dart';

const policy = StreamingPolicy(
  readAheadBytes: 1000,
  minBufferBytes: 200,
  stallAfter: Duration(seconds: 1),
  pollInterval: Duration(milliseconds: 10),
);

const hex = 'ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00';
const relativePath = 'Movie/a.mkv';

StreamingTarget target({int fileLength = 10000}) => StreamingTarget(
      infoHash: hex,
      relativePath: relativePath,
      localPath: '/storage/$relativePath',
      fileLengthBytes: fileLength,
      title: 'a.mkv',
    );

FakeTorrentEngine engine({int fileLength = 10000, int? peers, int? bps}) => FakeTorrentEngine(
      fileLengthBytes: fileLength,
      relativePath: relativePath,
      pieceLength: 100,
      infoHash: hex,
      numPeers: peers ?? 4,
      downloadBps: bps ?? 512 * 1024,
    );

StreamingPlaybackController session(
  FakeTorrentEngine e, {
  int fileLength = 10000,
  DateTime Function()? now,
}) =>
    StreamingPlaybackController(
      engine: e,
      target: target(fileLength: fileLength),
      policy: policy,
      autoPoll: false,
      now: now,
    );

void main() {
  group('session start', () {
    test('opens the window at the playhead and reports buffering honestly', () async {
      final e = engine();
      final c = session(e);
      await c.start();

      expect(e.beginCalls, hasLength(1));
      final request = e.beginCalls.single;
      expect(request.infoHash, hex);
      expect(request.relativePath, relativePath);
      expect(request.firstPiece, 0);
      expect(request.lastPiece, 9, reason: '1000-byte window over 100-byte pieces');
      expect(request.deadlineMs, policy.deadlineMs);
      expect(request.stepMs, policy.deadlineStepMs);

      expect(c.state.phase, StreamingPhase.buffering);
      expect(c.state.canPlay, isFalse);
      expect(c.state.requiredBytes, 250);
      expect(c.prioritisedStartByte, 0);
      c.dispose();
    });

    test('probes the piece geometry once, then reuses it', () async {
      final e = engine();
      final c = session(e);
      await c.start();
      expect(e.snapshotCalls, 1, reason: 'one probe for piece geometry');

      c.followPosition(const Duration(seconds: 6), const Duration(seconds: 100));
      await pumpEventQueue();
      expect(e.snapshotCalls, 1, reason: 'a later window must not re-probe');
      expect(e.beginCalls, hasLength(2));
      c.dispose();
    });

    test('a missing file fails with the engine message, not a fake buffer', () async {
      final e = engine();
      e.streamError = const TorrentEngineException(
        'FILE_NOT_FOUND',
        'That file is not part of this torrent\'s current file list.',
      );
      final c = session(e);
      await c.start();

      expect(c.state.phase, StreamingPhase.failed);
      expect(c.state.canPlay, isFalse);
      expect(c.state.message, contains('not part of this torrent'));
      expect(c.isPolling, isFalse);

      // Polling again must not throw or change the verdict.
      await c.poll();
      expect(c.state.phase, StreamingPhase.failed);
      c.dispose();
    });

    test('a completed file goes straight to complete, releases, and stops polling', () async {
      final e = engine(fileLength: 300);
      e.have.addAll({0, 1, 2});
      final c = StreamingPlaybackController(
        engine: e,
        target: target(fileLength: 300),
        policy: policy,
        autoPoll: true,
      );
      await c.start();
      await pumpEventQueue();

      expect(c.state.phase, StreamingPhase.complete);
      expect(c.state.canPlay, isTrue);
      expect(e.endCalls, hasLength(1), reason: 'priority handed back to the selection');
      expect(c.isPolling, isFalse, reason: 'nothing left to fetch, so nothing to poll');
      c.dispose();
    });
  });

  group('buffering feedback', () {
    test('data arriving turns the session ready with real byte counts', () async {
      final e = engine();
      final c = session(e);
      await c.start();
      expect(c.state.phase, StreamingPhase.buffering);

      e.have.addAll({0, 1, 2});
      await c.poll();

      expect(c.state.phase, StreamingPhase.ready);
      expect(c.state.canPlay, isTrue);
      expect(c.state.bufferedBytes, 300);
      expect(c.state.requiredBytes, 250);
      expect(c.state.bufferPercent, 1.0);
      c.dispose();
    });

    test('a flat buffer is reported as stalled and clears when data arrives', () async {
      var now = DateTime(2026, 1, 1);
      final e = engine(peers: 0, bps: 0);
      final c = session(e, now: () => now);
      await c.start();
      expect(c.state.phase, StreamingPhase.buffering);

      now = now.add(const Duration(seconds: 2));
      await c.poll();
      expect(c.state.phase, StreamingPhase.stalled);
      expect(c.state.message, contains('0 peer(s)'));
      expect(c.state.message, contains('no download speed'));

      e.have.addAll({0, 1, 2});
      await c.poll();
      expect(c.state.phase, StreamingPhase.ready);
      c.dispose();
    });

    test('an engine failure mid-session fails the session instead of freezing it', () async {
      final e = engine();
      final c = session(e);
      await c.start();

      e.streamError = const TorrentEngineException('ENGINE_UNAVAILABLE', 'The engine is gone.');
      await c.poll();

      expect(c.state.phase, StreamingPhase.failed);
      expect(c.state.message, 'The engine is gone.');
      expect(c.isPolling, isFalse);
      c.dispose();
    });
  });

  group('window follows the playhead', () {
    test('small movements do not reset the window', () async {
      final e = engine();
      final c = session(e);
      await c.start();

      // 1% of a 10000-byte file is 100 bytes: well inside the 500-byte trigger.
      c.followPosition(const Duration(seconds: 1), const Duration(seconds: 100));
      await pumpEventQueue();

      expect(e.beginCalls, hasLength(1));
      c.dispose();
    });

    test('the window slides once the playhead consumes half of it', () async {
      final e = engine();
      final c = session(e);
      await c.start();

      c.followPosition(const Duration(seconds: 6), const Duration(seconds: 100));
      await pumpEventQueue();

      expect(e.beginCalls, hasLength(2));
      expect(e.beginCalls.last.firstPiece, 6);
      expect(c.prioritisedStartByte, 600);
      c.dispose();
    });

    test('a seek backwards always re-aims', () async {
      final e = engine();
      final c = session(e);
      await c.start();
      c.followPosition(const Duration(seconds: 99), const Duration(seconds: 100));
      await pumpEventQueue();
      expect(c.prioritisedStartByte, 9900);

      c.followPosition(const Duration(seconds: 5), const Duration(seconds: 100));
      await pumpEventQueue();
      expect(c.prioritisedStartByte, 500);
      expect(e.beginCalls.last.firstPiece, 5);
      c.dispose();
    });

    test('the buffer target shrinks near the end of the file', () async {
      final e = engine();
      final c = session(e);
      await c.start();
      expect(c.state.requiredBytes, 250);

      // 99% of the way through: only 100 bytes are left to fetch and need.
      c.followPosition(const Duration(seconds: 99), const Duration(seconds: 100));
      await pumpEventQueue();

      expect(c.prioritisedStartByte, 9900);
      expect(c.state.requiredBytes, 100);
      c.dispose();
    });

    test('the tail can be prioritised for a container index at the end', () async {
      final e = engine();
      final c = session(e);
      await c.start();

      c.anchorAtByte(9600);
      await pumpEventQueue();

      expect(e.beginCalls.last.firstPiece, 96);
      expect(e.beginCalls.last.lastPiece, 99);
      expect(c.prioritisedStartByte, 9600);
      c.dispose();
    });

    test('a position that cannot be mapped is refused rather than guessed', () async {
      final e = engine();
      final c = session(e);
      await c.start();

      expect(c.anchorAtPosition(const Duration(seconds: 5), Duration.zero), isFalse);
      await pumpEventQueue();
      expect(e.beginCalls, hasLength(1), reason: 'the window is left where it was');
      c.dispose();
    });
  });

  group('session teardown', () {
    test('end() releases the window once', () async {
      final e = engine();
      final c = session(e);
      await c.start();
      await c.end();
      await c.end();
      expect(e.endCalls, hasLength(1));
      c.dispose();
    });

    test('disposing without end() still releases the window', () async {
      final e = engine();
      final c = session(e);
      await c.start();
      c.dispose();
      await pumpEventQueue();
      expect(e.endCalls, hasLength(1));
    });

    test('disposing stops the poll loop', () async {
      final e = engine();
      final c = StreamingPlaybackController(
        engine: e,
        target: target(),
        policy: policy,
        autoPoll: true,
      );
      await c.start();
      expect(c.isPolling, isTrue);
      c.dispose();
      expect(c.isPolling, isFalse);
      final calls = e.snapshotCalls;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(e.snapshotCalls, calls, reason: 'no polling after dispose');
    });
  });
}
