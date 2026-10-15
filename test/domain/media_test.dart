import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/domain/media/drm.dart';
import 'package:torrentlens/domain/media/media_classifier.dart';
import 'package:torrentlens/domain/media/media_resource.dart';
import 'package:torrentlens/domain/media/stream_manifest.dart';

void main() {
  group('MediaClassifier', () {
    test('uses MIME type when it is definitive', () {
      expect(
          MediaClassifier.classify(url: 'https://x/playlist', mimeType: 'application/vnd.apple.mpegurl').kind,
          MediaKind.hls);
      expect(MediaClassifier.classify(url: 'https://x/v', mimeType: 'video/mp4').kind, MediaKind.directVideo);
    });

    test('prefers a definitive MIME type over a conflicting extension', () {
      final r = MediaClassifier.classify(url: 'https://x/movie.mp4', mimeType: 'text/html');
      expect(r.kind, MediaKind.webPage);
      expect(r.evidence.any((e) => e.contains('conflicts')), isTrue);
    });

    test('falls back to the extension when MIME is absent', () {
      expect(MediaClassifier.classify(url: 'https://x/a/c.cbz').kind, MediaKind.comicArchive);
      expect(MediaClassifier.classify(url: 'https://x/a/c.m3u8').kind, MediaKind.hls);
      expect(MediaClassifier.classify(url: 'https://x/a/c.srt').kind, MediaKind.subtitle);
      expect(MediaClassifier.classify(url: 'https://x/a/c.torrent').kind, MediaKind.torrentFile);
    });

    test('routes magnet links and unsafe schemes', () {
      final mag = MediaClassifier.classify(url: 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567');
      expect(mag.kind, MediaKind.magnet);
      expect(mag.action, MediaAction.addTorrent);
      final bad = MediaClassifier.classify(url: 'javascript:alert(1)');
      expect(bad.kind, MediaKind.unsupported);
      expect(bad.action, MediaAction.explainUnsupported);
    });

    test('treats an unknown http URL as a web page, not a download', () {
      expect(MediaClassifier.classify(url: 'https://x/some/page').kind, MediaKind.webPage);
    });

    test('surfaces DRM-protected media with an evaluate action', () {
      final r = MediaClassifier.classify(url: 'https://x/s.mpd', hasWidevineData: true);
      expect(r.kind, MediaKind.drmProtected);
      expect(r.action, MediaAction.evaluateDrm);
      expect(r.isProtected, isTrue);
    });
  });

  group('StreamManifestParser', () {
    test('parses an HLS master playlist with variants and subtitles', () {
      const m3u8 = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",URI="subs/en.vtt"
#EXT-X-STREAM-INF:BANDWIDTH=1280000,RESOLUTION=1280x720,CODECS="avc1.4d401f"
720p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=640000,RESOLUTION=640x360
360p/index.m3u8
''';
      final m = StreamManifestParser.tryParse(m3u8, urlHint: 'https://cdn.example.com/hls/master.m3u8')!;
      expect(m.format, StreamFormat.hls);
      expect(m.isMaster, isTrue);
      expect(m.variants.length, 2);
      expect(m.variants.first.url, 'https://cdn.example.com/hls/720p/index.m3u8');
      expect(m.variants.first.bandwidthBps, 1280000);
      expect(m.subtitleTracks['English'], 'https://cdn.example.com/hls/subs/en.vtt');
    });

    test('sums EXTINF durations on a media playlist', () {
      const m3u8 = '#EXTM3U\n#EXTINF:4.0,\nseg0.ts\n#EXTINF:4.0,\nseg1.ts\n#EXTINF:2.5,\nseg2.ts\n';
      final m = StreamManifestParser.tryParse(m3u8)!;
      expect(m.isMaster, isFalse);
      expect(m.durationSeconds, 11);
    });

    test('parses a DASH MPD duration and representations', () {
      const mpd = '''
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" mediaPresentationDuration="PT1H2M3S">
  <Period>
    <AdaptationSet>
      <Representation id="1" bandwidth="800000" width="1280" height="720" codecs="avc1"/>
    </AdaptationSet>
  </Period>
</MPD>''';
      final m = StreamManifestParser.tryParse(mpd)!;
      expect(m.format, StreamFormat.dash);
      expect(m.durationSeconds, 3723);
      expect(m.variants.single.bandwidthBps, 800000);
    });

    test('returns null for unrelated text instead of throwing', () {
      expect(StreamManifestParser.tryParse('hello world'), isNull);
      expect(StreamManifestParser.tryParse('<not-an-mpd/>'), isNull);
    });
  });

  group('DrmCapabilityDetector', () {
    test('detects Widevine from a ContentProtection UUID', () {
      final a = DrmCapabilityDetector.assess(
          manifestText: 'urn:uuid:EDEF8BA9-79D6-4ACE-A3C8-27DCD51D21ED');
      expect(a.isProtected, isTrue);
      expect(a.indicators.any((i) => i.system == DrmSystem.widevine), isTrue);
      expect(a.mayBePlayableIfAuthorized, isTrue);
    });

    test('reports no protection for a plain manifest', () {
      final a = DrmCapabilityDetector.assess(manifestText: '<MPD></MPD>');
      expect(a.isProtected, isFalse);
    });

    test('explains that FairPlay alone is not playable on Android', () {
      final a = DrmCapabilityDetector.assess(
          manifestText: 'urn:uuid:94CE86FB-07FF-4F43-ADB8-93D2FA968CA2');
      expect(a.isProtected, isTrue);
      expect(a.mayBePlayableIfAuthorized, isFalse);
    });
  });

  group('AuthorizedPlaybackAdapter', () {
    const protectedText = 'urn:uuid:EDEF8BA9-79D6-4ACE-A3C8-27DCD51D21ED';

    DrmPlaybackRequest req({Map<String, String> headers = const {}}) =>
        DrmPlaybackRequest(
          source: Uri.parse('https://cdn.example.com/movie/manifest.mpd'),
          assessment: DrmCapabilityDetector.assess(manifestText: protectedText),
          licenseUrl: Uri.parse('https://license.example.com/widevine'),
          assetId: 'asset-1',
          headers: headers,
        );

    test('the default adapter fails closed: it never claims playback', () async {
      const adapter = UnconfiguredAuthorizedPlaybackAdapter();
      final result = await adapter.authorize(req());

      expect(adapter.providerName, isNull);
      expect(result.outcome, DrmAuthorizationOutcome.providerNotConfigured);
      expect(result.canPlay, isFalse);
      expect(result.authorizedSource, isNull);
      expect(result.message, contains('official app'));
    });

    test('describe() exposes no token from the request headers', () {
      final request = req(headers: {'Authorization': 'Bearer secret-token'});
      final described = request.describe;

      expect(described, contains('cdn.example.com'));
      expect(described, isNot(contains('secret-token')));
      expect(described, isNot(contains('Bearer')));
    });

    test('a custom adapter can authorise, and only then is canPlay true', () async {
      final adapter = _FakeAdapter();
      final result = await adapter.authorize(req());

      expect(result.outcome, DrmAuthorizationOutcome.authorized);
      expect(result.canPlay, isTrue);
      expect(result.authorizedSource.toString(),
          'https://cdn.example.com/movie/signed.mpd');
    });

    test('a provider refusal is a distinct outcome, not a generic failure', () async {
      final adapter = _FakeAdapter(
        outcome: DrmAuthorizationOutcome.licenseUnavailable,
        message: 'The license server did not return a license.',
      );
      final result = await adapter.authorize(req());

      expect(result.canPlay, isFalse);
      expect(result.outcome, DrmAuthorizationOutcome.licenseUnavailable);
    });
  });
}

class _FakeAdapter implements AuthorizedPlaybackAdapter {
  @override
  String? get providerName => 'Example Provider';

  final DrmAuthorizationOutcome outcome;
  final String message;

  _FakeAdapter({
    this.outcome = DrmAuthorizationOutcome.authorized,
    this.message = 'Authorised for this device.',
  });

  @override
  Future<DrmAuthorizationResult> authorize(DrmPlaybackRequest request) async {
    return DrmAuthorizationResult(
      outcome: outcome,
      message: message,
      authorizedSource: outcome == DrmAuthorizationOutcome.authorized
          ? Uri.parse('https://cdn.example.com/movie/signed.mpd')
          : null,
      playbackHeaders: outcome == DrmAuthorizationOutcome.authorized
          ? const {'Authorization': 'Bearer signed'}
          : const {},
    );
  }
}
