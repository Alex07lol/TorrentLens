import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/domain/torrent/streaming.dart';
import 'package:torrentlens/integrations/torrent/torrent_engine.dart';

StreamSnapshot snap({
  int fileLength = 1000,
  int pieceLength = 100,
  int fileOffset = 0,
  Set<int> have = const {},
  bool complete = false,
  String state = 'downloading',
  int peers = 1,
  int seeds = 0,
  int bps = 0,
  int? doneBytes,
}) {
  final firstFilePiece = fileOffset ~/ pieceLength;
  final lastFilePiece = (fileOffset + (fileLength > 0 ? fileLength : 1) - 1) ~/ pieceLength;
  final done = doneBytes ?? have.length * pieceLength;
  return StreamSnapshot(
    infoHash: 'ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00',
    relativePath: 'Movie/a.mkv',
    fileIndex: 0,
    fileLengthBytes: fileLength,
    fileOffsetInTorrent: fileOffset,
    pieceLength: pieceLength,
    firstFilePiece: firstFilePiece,
    lastFilePiece: lastFilePiece,
    fileDoneBytes: done,
    fileComplete: complete,
    rangeFirstPiece: firstFilePiece,
    rangeLastPiece: lastFilePiece,
    piecesHave: have.toList(),
    downloadBps: bps,
    uploadBps: 0,
    numPeers: peers,
    numSeeds: seeds,
    state: state,
    progress: fileLength == 0 ? 1 : done / fileLength,
  );
}

const small = StreamingPolicy(readAheadBytes: 1000, minBufferBytes: 200);

void main() {
  group('StreamingPolicy.windowFor', () {
    const p = small;

    test('covers the read-ahead from the playhead', () {
      final w = p.windowFor(snap(fileLength: 10000), 0);
      expect(w.firstPiece, 0);
      expect(w.lastPiece, 9);
      expect(w.windowBytes, 1000);
      expect(w.startByteInTorrent, 0);
      expect(w.endByteInTorrent, 1000);
    });

    test('starts at the playhead piece when the playhead is mid-piece', () {
      final w = p.windowFor(snap(fileLength: 10000), 550);
      expect(w.firstPiece, 5);
      expect(w.lastPiece, 15);
      expect(w.startByteInFile, 550);
      expect(w.startByteInTorrent, 550);
      expect(w.isPlayheadMidPiece(100), isTrue);
      expect(p.windowFor(snap(fileLength: 10000), 500).isPlayheadMidPiece(100), isFalse);
    });

    test('clamps the window to the end of the file', () {
      final w = p.windowFor(snap(fileLength: 10000), 9500);
      expect(w.firstPiece, 95);
      expect(w.lastPiece, 99);
      expect(w.windowBytes, 500);
    });

    test('a playhead at the file length still resolves to a real piece', () {
      final w = p.windowFor(snap(fileLength: 10000), 10000);
      expect(w.startByteInFile, 9999);
      expect(w.firstPiece, 99);
      expect(w.lastPiece, 99);
      expect(w.windowBytes, 1);
    });

    test('never leaves the file it belongs to in a multi-file torrent', () {
      // The file starts at torrent byte 1000 (piece 10) and is 250 bytes long.
      final multi = snap(fileLength: 250, fileOffset: 1000);
      expect(multi.firstFilePiece, 10);
      expect(multi.lastFilePiece, 12);

      final atStart = p.windowFor(multi, 0);
      expect(atStart.firstPiece, 10);
      expect(atStart.lastPiece, 12);

      final nearEnd = p.windowFor(multi, 200);
      expect(nearEnd.firstPiece, 12);
      expect(nearEnd.lastPiece, 12);
      expect(nearEnd.windowBytes, 50);
    });

    test('caps the piece count so a channel payload stays bounded', () {
      const policy = StreamingPolicy(); // 24 MiB read-ahead, 512-piece cap
      final w = policy.windowFor(snap(fileLength: 200000, pieceLength: 100), 0);
      expect(w.pieceCount, policy.maxWindowPieces);
      expect(w.firstPiece, 0);
      expect(w.lastPiece, 511);
    });

    test('a zero-length file does not produce an empty or invalid range', () {
      final w = p.windowFor(snap(fileLength: 0), 0);
      expect(w.pieceCount, 1);
      expect(w.windowBytes, 0);
    });

    test('a playhead past the end is clamped rather than throwing', () {
      final w = p.windowFor(snap(fileLength: 500), 99999);
      expect(w.startByteInFile, 499);
      expect(w.firstPiece, 4);
      expect(w.lastPiece, 4);
    });
  });

  group('StreamingPolicy.contiguousBytes', () {
    const p = small;

    test('counts only an unbroken run from the window start', () {
      final w = p.windowFor(snap(fileLength: 10000), 0);
      int measure(Set<int> have) => p.contiguousBytes(
            window: w,
            have: have,
            pieceLength: 100,
            windowStartByteInTorrent: w.startByteInTorrent,
          );

      expect(measure({}), 0);
      expect(measure({0, 1, 2}), 300);
      expect(measure({0, 1, 3}), 200, reason: 'a gap at piece 2 stops the run');
      expect(measure({1, 2, 3}), 0, reason: 'the window start piece is missing');
      expect(measure({for (var i = 0; i <= 40; i++) i}), 1000, reason: 'clamped to the window');
    });

    test('subtracts the part of the first piece behind the playhead', () {
      final w = p.windowFor(snap(fileLength: 10000), 550);
      int measure(Set<int> have) => p.contiguousBytes(
            window: w,
            have: have,
            pieceLength: 100,
            windowStartByteInTorrent: w.startByteInTorrent,
          );

      expect(measure({5}), 50);
      expect(measure({5, 6}), 150);
      expect(measure({6}), 0);
      expect(measure({for (var i = 5; i <= 15; i++) i}), 1000);
    });

    test('reports the short final window exactly', () {
      final w = p.windowFor(snap(fileLength: 10000), 9500);
      expect(
        p.contiguousBytes(
          window: w,
          have: {95, 96, 97, 98, 99},
          pieceLength: 100,
          windowStartByteInTorrent: w.startByteInTorrent,
        ),
        500,
      );
    });

    test('degenerates safely on impossible geometry', () {
      final w = p.windowFor(snap(fileLength: 0), 0);
      expect(
        p.contiguousBytes(window: w, have: {0}, pieceLength: 0, windowStartByteInTorrent: 0),
        0,
      );
    });
  });

  group('StreamingPolicy.requiredBufferBytes', () {
    test('a quarter of the read-ahead, floored at the minimum', () {
      const policy = StreamingPolicy(); // 24 MiB read-ahead, 4 MiB floor
      const mib = 1024 * 1024;
      expect(policy.requiredBufferBytes(fileLengthBytes: 100 * mib, startByteInFile: 0), 6 * mib);
      expect(policy.requiredBufferBytes(fileLengthBytes: 5 * mib, startByteInFile: 0), 5 * mib);
      expect(
        policy.requiredBufferBytes(fileLengthBytes: 100 * mib, startByteInFile: 99 * mib),
        1 * mib,
        reason: 'never asks for more than the file has left',
      );
      expect(policy.requiredBufferBytes(fileLengthBytes: 0, startByteInFile: 0), 0);
    });

    test('honours a custom read-ahead and floor', () {
      expect(small.requiredBufferBytes(fileLengthBytes: 1000, startByteInFile: 0), 250);
      expect(small.requiredBufferBytes(fileLengthBytes: 300, startByteInFile: 0), 250);
      expect(small.requiredBufferBytes(fileLengthBytes: 300, startByteInFile: 200), 100);
    });
  });

  group('StreamingPolicy.evaluate', () {
    const policy = StreamingPolicy(
      readAheadBytes: 1000,
      minBufferBytes: 200,
      stallAfter: Duration(milliseconds: 500),
    );

    StreamingPlaybackState evaluate(
      StreamSnapshot s, {
      required int contiguous,
      Duration sinceProgress = Duration.zero,
    }) =>
        policy.evaluate(
          snapshot: s,
          window: policy.windowFor(s, 0),
          contiguousBytes: contiguous,
          sinceProgress: sinceProgress,
        );

    test('metadata still resolving is its own phase', () {
      final st = evaluate(snap(state: 'resolvingMetadata'), contiguous: 0);
      expect(st.phase, StreamingPhase.resolvingMetadata);
      expect(st.canPlay, isFalse);
      expect(st.message, contains('metadata'));
    });

    test('a finished file is complete and needs no peers', () {
      final st = evaluate(snap(complete: true, state: 'completed'), contiguous: 0);
      expect(st.phase, StreamingPhase.complete);
      expect(st.canPlay, isTrue);
      expect(st.isFinished, isTrue);
      expect(st.requiredBytes, 0);
      expect(st.message, contains('Fully downloaded'));
    });

    test('an unavailable torrent fails rather than pretending to buffer', () {
      final st = evaluate(snap(state: 'unavailable'), contiguous: 0);
      expect(st.phase, StreamingPhase.failed);
      expect(st.canPlay, isFalse);
      expect(st.message, contains('unavailable'));
    });

    test('below the required depth it buffers and reports the fraction', () {
      final st = evaluate(snap(fileLength: 10000), contiguous: 100);
      expect(st.phase, StreamingPhase.buffering);
      expect(st.canPlay, isFalse);
      expect(st.bufferPercent, closeTo(100 / 250, 0.0001));
      expect(st.bufferedBytes, 100);
      expect(st.requiredBytes, 250);
    });

    test('exactly the required depth is ready', () {
      final st = evaluate(snap(fileLength: 10000), contiguous: 250);
      expect(st.phase, StreamingPhase.ready);
      expect(st.canPlay, isTrue);
      expect(st.bufferPercent, 1.0);
    });

    test('a flat buffer over the stall window is stalled, not merely buffering', () {
      final st = evaluate(
        snap(fileLength: 10000, bps: 0),
        contiguous: 100,
        sinceProgress: const Duration(milliseconds: 500),
      );
      expect(st.phase, StreamingPhase.stalled);
      expect(st.message, contains('peer(s)'));
      expect(st.message, contains('no download speed'));
    });

    test('a stall never overrides an already playable buffer', () {
      final st = evaluate(
        snap(fileLength: 10000, bps: 0),
        contiguous: 250,
        sinceProgress: const Duration(seconds: 30),
      );
      expect(st.phase, StreamingPhase.ready);
      expect(st.canPlay, isTrue);
    });
  });

  group('StreamingPolicy.shouldReprioritise', () {
    test('does nothing until the playhead consumes half the window', () {
      expect(small.shouldReprioritise(lastPrioritisedStartByte: 0, newStartByte: 0), isFalse);
      expect(small.shouldReprioritise(lastPrioritisedStartByte: 0, newStartByte: 499), isFalse);
      expect(small.shouldReprioritise(lastPrioritisedStartByte: 0, newStartByte: 500), isTrue);
      expect(small.shouldReprioritise(lastPrioritisedStartByte: 500, newStartByte: 900), isFalse);
    });

    test('always re-aims when the playhead moves backwards', () {
      expect(small.shouldReprioritise(lastPrioritisedStartByte: 900, newStartByte: 100), isTrue);
    });
  });

  group('StreamingPolicy.byteOffsetForPosition', () {
    test('maps a position onto the file proportionally', () {
      expect(
        small.byteOffsetForPosition(
          position: const Duration(seconds: 50),
          duration: const Duration(seconds: 100),
          fileLengthBytes: 1000,
        ),
        500,
      );
    });

    test('clamps positions outside the media', () {
      expect(
        small.byteOffsetForPosition(
          position: const Duration(seconds: 200),
          duration: const Duration(seconds: 100),
          fileLengthBytes: 1000,
        ),
        999,
      );
      expect(
        small.byteOffsetForPosition(
          position: const Duration(seconds: -5),
          duration: const Duration(seconds: 100),
          fileLengthBytes: 1000,
        ),
        0,
      );
    });

    test('returns null instead of guessing when the mapping is unknown', () {
      expect(
        small.byteOffsetForPosition(
          position: const Duration(seconds: 5),
          duration: Duration.zero,
          fileLengthBytes: 1000,
        ),
        isNull,
      );
      expect(
        small.byteOffsetForPosition(
          position: const Duration(seconds: 5),
          duration: const Duration(seconds: 10),
          fileLengthBytes: 0,
        ),
        isNull,
      );
    });
  });
}
