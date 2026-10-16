import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/domain/torrent/torrent_payload.dart';
import 'package:torrentlens/features/downloads/torrent_fetch.dart';
import 'package:torrentlens/integrations/media_resolver/http_fetcher.dart';

/// Records every binary GET so the tests can assert hop-by-hop behaviour.
class FakeBinaryFetcher extends HttpFetcher {
  final Map<String, HttpFetchBytes> routes;
  final List<Uri> requested = [];
  bool? lastFollowRedirects;

  FakeBinaryFetcher(this.routes);

  @override
  Future<HttpFetchResponse> get(Uri url,
          {bool followRedirects = true,
          int maxBytes = 512 * 1024,
          Map<String, String>? headers,
          Duration timeout = const Duration(seconds: 20)}) async =>
      throw UnsupportedError('this test only exercises getBytes');

  @override
  Future<HttpFetchBytes> getBytes(Uri url,
      {bool followRedirects = true,
      int maxBytes = 8 * 1024 * 1024,
      Map<String, String>? headers,
      Duration timeout = const Duration(seconds: 30)}) async {
    requested.add(url);
    lastFollowRedirects = followRedirects;
    final r = routes[url.toString()];
    if (r == null) throw StateError('no route for $url');
    return r;
  }
}

HttpFetchBytes bytesResponse(String url, int status, List<int> body,
        {Map<String, String> headers = const {}, bool truncated = false}) =>
    HttpFetchBytes(
      finalUrl: Uri.parse(url),
      statusCode: status,
      headers: headers,
      bytes: Uint8List.fromList(body),
      truncated: truncated,
    );

/// A bencoded torrent whose `pieces` field contains every byte value >= 0x80,
/// i.e. exactly the data a UTF-8 decode/re-encode round-trip destroys.
Uint8List binaryTorrent() {
  const announce = 'https://tracker.example/announce';
  const name = 'video.mkv';
  final pieces = List<int>.generate(20, (i) => 0x80 + i);
  final out = <int>[];
  void s(String v) => out.addAll(v.codeUnits);
  // Keys must be in bencode (byte) order: announce < info, length < name < pieces.
  s('d8:announce${announce.length}:$announce');
  s('4:infod6:lengthi4096e4:name${name.length}:${name}6:pieces20:');
  out.addAll(pieces);
  s('ee');
  return Uint8List.fromList(out);
}

void main() {
  group('TorrentPayload', () {
    test('accepts a real bencoded torrent', () {
      expect(TorrentPayload.describeProblem(binaryTorrent()), isNull);
    });

    test('reports an HTML error page as a web page, not a torrent', () {
      final html = Uint8List.fromList('<html><body>404</body></html>'.codeUnits);
      expect(TorrentPayload.looksLikeText(html), isTrue);
      expect(TorrentPayload.describeProblem(html), contains('web page'));
    });

    test('rejects empty and stub responses', () {
      expect(TorrentPayload.describeProblem(Uint8List(0)), contains('empty'));
      expect(TorrentPayload.describeProblem(Uint8List.fromList('d1:x'.codeUnits)),
          contains('too small'));
    });
  });

  group('TorrentFileFetcher', () {
    const url = 'https://host.example/files/release.torrent';

    test('returns the original bytes byte-for-byte (regression: UTF-8 round-trip)',
        () async {
      final payload = binaryTorrent();
      final f = FakeBinaryFetcher({
        url: bytesResponse(url, 200, payload, headers: {
          'content-type': 'application/x-bittorrent',
          'content-length': '${payload.length}',
        }),
      });
      final result = await TorrentFileFetcher(f).fetch(url);
      expect(result.ok, isTrue);
      expect(result.bytes, orderedEquals(payload));
      // The exact corruption the old code produced: every byte >= 0x80 became
      // two UTF-8 bytes, so the lengths differed.
      expect(result.bytes!.length, payload.length);
      expect(result.finalUrl.toString(), url);
      expect(f.lastFollowRedirects, isFalse, reason: 'hops must be validated by us');
    });

    test('follows redirects one hop at a time and reports the destination', () async {
      final payload = binaryTorrent();
      final f = FakeBinaryFetcher({
        url: bytesResponse(url, 302, const [], headers: {'location': '/mirror/a.torrent'}),
        'https://host.example/mirror/a.torrent': bytesResponse(
            'https://host.example/mirror/a.torrent', 200, payload,
            headers: {'content-type': 'application/octet-stream'}),
      });
      final result = await TorrentFileFetcher(f).fetch(url);
      expect(result.ok, isTrue);
      expect(result.finalUrl.toString(), 'https://host.example/mirror/a.torrent');
      expect(f.requested.length, 2);
    });

    test('refuses a redirect into a private address', () async {
      final f = FakeBinaryFetcher({
        url: bytesResponse(url, 302, const [], headers: {'location': 'http://127.0.0.1/x.torrent'}),
      });
      final result = await TorrentFileFetcher(f).fetch(url);
      expect(result.error, TorrentFetchError.unsafeUrl);
      expect(f.requested.length, 1);
    });

    test('stops after the redirect limit', () async {
      final routes = <String, HttpFetchBytes>{};
      for (var i = 0; i < 12; i++) {
        routes['https://host.example/$i'] =
            bytesResponse('https://host.example/$i', 302, const [], headers: {'location': '/${i + 1}'});
      }
      final result = await TorrentFileFetcher(FakeBinaryFetcher(routes))
          .fetch('https://host.example/0');
      expect(result.error, TorrentFetchError.tooManyRedirects);
    });

    test('refuses to fetch from a private or non-http address at all', () async {
      final f = FakeBinaryFetcher({});
      expect((await TorrentFileFetcher(f).fetch('http://10.0.0.5/a.torrent')).error,
          TorrentFetchError.unsafeUrl);
      expect((await TorrentFileFetcher(f).fetch('ftp://host/a.torrent')).error,
          TorrentFetchError.unsafeUrl);
      expect(f.requested, isEmpty);
    });

    test('rejects HTTP errors, HTML bodies and oversized responses', () async {
      final html = Uint8List.fromList('<!DOCTYPE html><p>not found</p>'.codeUnits);
      expect(
          (await TorrentFileFetcher(FakeBinaryFetcher({url: bytesResponse(url, 404, const [])}))
                  .fetch(url))
              .error,
          TorrentFetchError.httpError);
      expect(
          (await TorrentFileFetcher(FakeBinaryFetcher({
            url: bytesResponse(url, 200, html, headers: {'content-type': 'text/html; charset=utf-8'})
          })).fetch(url))
              .error,
          TorrentFetchError.notATorrent);
      // No content-type at all, but the body is plainly a web page.
      expect(
          (await TorrentFileFetcher(FakeBinaryFetcher({url: bytesResponse(url, 200, html)}))
                  .fetch(url))
              .error,
          TorrentFetchError.notATorrent);
      expect(
          (await TorrentFileFetcher(FakeBinaryFetcher({
            url: bytesResponse(url, 200, const [0x64], headers: {'content-length': '99999999'})
          })).fetch(url))
              .error,
          TorrentFetchError.tooLarge);
      expect(
          (await TorrentFileFetcher(FakeBinaryFetcher({
            url: bytesResponse(url, 200, binaryTorrent(), truncated: true)
          })).fetch(url))
              .error,
          TorrentFetchError.tooLarge);
    });
  });
}
