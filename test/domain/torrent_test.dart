import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/domain/torrent/info_hash.dart';
import 'package:torrentlens/domain/torrent/magnet_uri.dart';
import 'package:torrentlens/domain/torrent/task_state.dart';
import 'package:torrentlens/domain/torrent/torrent_source.dart';

void main() {
  group('InfoHash', () {
    test('parses 40-char hex and round-trips', () {
      const hex = '0123456789abcdef0123456789abcdef01234567';
      final h = InfoHash.tryParse(hex);
      expect(h, isNotNull);
      expect(h!.bytes.length, 20);
      expect(h.toHex(), hex);
    });

    test('parses base32 into the same digest as hex (independent vector)', () {
      const hex = 'de9edb7d7b7dc1b4d35b61c2ece435373f8343c8';
      const b32 = '32PNW7L3PXA3JU23MHBOZZBVG47YGQ6I';
      expect(InfoHash.tryParse(b32)!.toHex(), hex);
    });

    test('rejects wrong lengths and bad alphabets', () {
      expect(InfoHash.tryParse('deadbeef'), isNull);
      expect(InfoHash.tryParse('z' * 40), isNull);
      expect(InfoHash.tryParse('0000000000000000000000000000000000000000000'), isNull);
    });
  });

  group('MagnetUri', () {
    const hex = '0123456789abcdef0123456789abcdef01234567';

    test('parses hash, display name, trackers and web seeds', () {
      final m = MagnetUri.parse(
          'magnet:?xt=urn:btih:$hex&dn=My%20Book&tr=udp%3A%2F%2Ftr.example%3A80&tr=wss://x&ws=https%3A%2F%2Fseed%2Ff');
      expect(m.infoHash.toHex(), hex);
      expect(m.displayName, 'My Book');
      expect(m.trackers, ['udp://tr.example:80', 'wss://x']);
      expect(m.webSeeds, ['https://seed/f']);
    });

    test('rejects a non-magnet string', () {
      expect(() => MagnetUri.parse('https://example.com/a.torrent'),
          throwsA(isA<MagnetUriParseException>()
              .having((e) => e.error, 'error', MagnetParseError.notAMagnet)));
    });

    test('reports a missing info-hash distinctly', () {
      expect(() => MagnetUri.parse('magnet:?dn=x'),
          throwsA(isA<MagnetUriParseException>()
              .having((e) => e.error, 'error', MagnetParseError.missingInfoHash)));
    });

    test('reports an invalid info-hash distinctly', () {
      expect(() => MagnetUri.parse('magnet:?xt=urn:btih:nothex'),
          throwsA(isA<MagnetUriParseException>()
              .having((e) => e.error, 'error', MagnetParseError.invalidInfoHash)));
    });

    test('rejects duplicate v1 info-hashes', () {
      expect(() => MagnetUri.parse('magnet:?xt=urn:btih:$hex&xt=urn:btih:$hex'),
          throwsA(isA<MagnetUriParseException>()
              .having((e) => e.error, 'error', MagnetParseError.duplicateInfoHash)));
    });

    test('reports v2-only magnets as unsupported rather than invalid', () {
      expect(() => MagnetUri.parse('magnet:?xt=urn:btmh:1220${'ab' * 32}'),
          throwsA(isA<MagnetUriParseException>()
              .having((e) => e.error, 'error', MagnetParseError.unsupportedHash)));
    });
  });

  group('TorrentSource', () {
    test('classifies magnet, .torrent URL and local file', () {
      expect(TorrentSource.classify('magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567').kind,
          TorrentSourceKind.magnet);
      expect(TorrentSource.classify('https://host/a.torrent').kind, TorrentSourceKind.torrentUrl);
      expect(TorrentSource.classify('/sdcard/x.torrent').kind, TorrentSourceKind.torrentFile);
    });
  });

  group('TorrentStateMachine', () {
    test('allows the normal lifecycle', () {
      expect(TorrentStateMachine.canTransition(TorrentTaskState.queued, TorrentTaskState.downloading), isTrue);
      expect(TorrentStateMachine.canTransition(TorrentTaskState.downloading, TorrentTaskState.seeding), isTrue);
      expect(TorrentStateMachine.canTransition(TorrentTaskState.seeding, TorrentTaskState.paused), isTrue);
      expect(TorrentStateMachine.canTransition(TorrentTaskState.paused, TorrentTaskState.downloading), isTrue);
    });

    test('rejects impossible transitions', () {
      expect(TorrentStateMachine.canTransition(TorrentTaskState.seeding, TorrentTaskState.queued), isFalse);
      expect(TorrentStateMachine.canTransition(TorrentTaskState.failed, TorrentTaskState.completed), isFalse);
      expect(() => TorrentStateMachine.transition(TorrentTaskState.seeding, TorrentTaskState.resolvingMetadata),
          throwsStateError);
    });

    test('identity transition is always allowed', () {
      for (final s in TorrentTaskState.values) {
        expect(TorrentStateMachine.canTransition(s, s), isTrue);
      }
    });
  });
}
