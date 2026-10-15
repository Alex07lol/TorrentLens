import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/domain/media/media_resource.dart';
import 'package:torrentlens/integrations/media_resolver/css_resource_extractor.dart';
import 'package:torrentlens/integrations/media_resolver/html_resource_extractor.dart';
import 'package:torrentlens/integrations/media_resolver/http_fetcher.dart';
import 'package:torrentlens/integrations/media_resolver/media_action_router.dart';
import 'package:torrentlens/integrations/media_resolver/media_link_resolver.dart';
import 'package:torrentlens/integrations/media_resolver/redirect_resolver.dart';
import 'package:torrentlens/integrations/media_resolver/script_resource_analyzer.dart';
import 'package:torrentlens/integrations/media_resolver/web_content_sandbox.dart';

class FakeFetcher extends HttpFetcher {
  final Map<String, HttpFetchResponse> routes;
  final List<Uri> requested = [];
  FakeFetcher(this.routes);

  @override
  Future<HttpFetchResponse> get(Uri url,
      {bool followRedirects = true,
      int maxBytes = 512 * 1024,
      Map<String, String>? headers,
      Duration timeout = const Duration(seconds: 20)}) async {
    requested.add(url);
    final r = routes[url.toString()];
    if (r == null) throw StateError('no route for $url');
    return r;
  }
}

HttpFetchResponse resp(String url, int status,
        {String body = '', Map<String, String> headers = const {}}) =>
    HttpFetchResponse(
        finalUrl: Uri.parse(url), statusCode: status, headers: headers, body: body);

void main() {
  group('HtmlResourceExtractor', () {
    test('extracts anchors, media elements, srcset and resolves relative URLs', () {
      const html = '''
<html><body>
  <a href="book.epub">Book</a>
  <a href="magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567">magnet</a>
  <video src="v/movie.mp4" poster="p.jpg"></video>
  <source src="stream/master.m3u8">
  <img src="cover.jpg" srcset="cover.jpg 1x, cover@2x.jpg 2x">
  <iframe src="https://embed.example.com/e/1"></iframe>
  <a href="javascript:alert(1)">bad</a>
</body></html>''';
      final links = HtmlResourceExtractor.extract(html, baseUrl: Uri.parse('https://site.example/dir/page.html'));
      final urls = links.map((l) => l.url).toList();
      expect(urls, contains('https://site.example/dir/book.epub'));
      expect(urls, contains('https://site.example/dir/v/movie.mp4'));
      expect(urls, contains('https://site.example/dir/stream/master.m3u8'));
      expect(urls, contains('https://site.example/dir/cover@2x.jpg'));
      expect(urls.any((u) => u.startsWith('magnet:')), isTrue);
      // javascript: href is not a usable absolute URL and is dropped/resolved away
      expect(urls.any((u) => u.startsWith('javascript:')), isFalse);
    });
  });

  group('CssResourceExtractor', () {
    test('extracts url() and @import against the stylesheet URL', () {
      const css = '''
@import "base.css";
.hero { background: url('../img/hero.jpg'); }
.icon { background-image: url("data:image/png;base64,AAAA"); }
''';
      final links = CssResourceExtractor.extract(css, stylesheetUrl: Uri.parse('https://cdn.example.com/css/app/main.css'));
      final urls = links.map((l) => l.url).toList();
      expect(urls, contains('https://cdn.example.com/css/app/base.css'));
      expect(urls, contains('https://cdn.example.com/css/img/hero.jpg'));
      expect(urls.any((u) => u.startsWith('data:')), isFalse);
    });
  });

  group('ScriptResourceAnalyzer', () {
    test('statically finds quoted media URLs without executing anything', () {
      const js = '''
        var player = new Player({ file: "stream/index.m3u8", poster: "poster.jpg" });
        var alt = "https://mirror.example.com/video/movie.mp4";
      ''';
      final links = ScriptResourceAnalyzer.extract(js, baseUrl: Uri.parse('https://site.example/a/b.html'));
      final urls = links.map((l) => l.url).toList();
      expect(urls, contains('https://site.example/a/stream/index.m3u8'));
      expect(urls, contains('https://mirror.example.com/video/movie.mp4'));
    });
  });

  group('RedirectResolver', () {
    test('follows same-origin redirects and reports the final URL', () async {
      final f = FakeFetcher({
        'https://a.example/x': resp('https://a.example/x', 302, headers: {'location': '/y'}),
        'https://a.example/y': resp('https://a.example/y', 200, body: 'ok'),
      });
      final r = await RedirectResolver(f).resolve(Uri.parse('https://a.example/x'));
      expect(r.isOk, isTrue);
      expect(r.valueOrNull!.finalUrl.toString(), 'https://a.example/y');
      expect(r.valueOrNull!.hops.length, 1);
    });

    test('refuses a redirect to a private address', () async {
      final f = FakeFetcher({
        'https://a.example/x': resp('https://a.example/x', 302, headers: {'location': 'http://127.0.0.1/secret'}),
      });
      final r = await RedirectResolver(f).resolve(Uri.parse('https://a.example/x'));
      expect(r.isErr, isTrue);
      expect(r.errorOrNull(), RedirectError.unsafeRedirect);
    });

    test('stops after the hop limit', () async {
      final routes = <String, HttpFetchResponse>{};
      for (var i = 0; i < 10; i++) {
        routes['https://a.example/$i'] =
            resp('https://a.example/$i', 302, headers: {'location': '/${i + 1}'});
      }
      final r = await RedirectResolver(FakeFetcher(routes), maxHops: 3)
          .resolve(Uri.parse('https://a.example/0'));
      expect(r.errorOrNull(), RedirectError.tooManyHops);
    });
  });

  group('MediaLinkResolver', () {
    const html = '''
<html><head><link rel="stylesheet" href="/css/app.css"></head><body>
  <video><source src="video/movie.mkv"></video>
  <a href="stream/master.m3u8">Watch</a>
  <a href="subs/en.srt">English</a>
  <a href="magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567">Magnet</a>
  <a href="https://cdn.example.com/file.torrent">Torrent</a>
  <a href="chapter5.epub">EPUB</a>
</body></html>''';

    test('classifies local HTML into routable resources', () {
      final r = MediaLinkResolver(FakeFetcher({}))
          .resolveFromHtml(html: html, baseUrl: Uri.parse('https://site.example/p/index.html'));
      final kinds = r.resources.map((e) => e.kind).toSet();
      expect(kinds, contains(MediaKind.directVideo));
      expect(kinds, contains(MediaKind.hls));
      expect(kinds, contains(MediaKind.subtitle));
      expect(kinds, contains(MediaKind.magnet));
      expect(kinds, contains(MediaKind.torrentFile));
      expect(kinds, contains(MediaKind.epub));
    });

    test('fetches a page, validates redirects and classifies its links', () async {
      final f = FakeFetcher({
        'https://site.example/p': resp('https://site.example/p', 302, headers: {'location': '/real'}),
        'https://site.example/real': resp('https://site.example/real', 200,
            body: html, headers: {'content-type': 'text/html; charset=utf-8'}),
      });
      final r = await MediaLinkResolver(f).resolveFromUrl('https://site.example/p');
      expect(r.isOk, isTrue);
      expect(r.valueOrNull!.pageUrl.toString(), 'https://site.example/real');
      expect(r.valueOrNull!.resources.any((e) => e.kind == MediaKind.hls), isTrue);
    });

    test('refuses to fetch a private or unsafe URL', () async {
      final resolver = MediaLinkResolver(FakeFetcher({}));
      expect((await resolver.resolveFromUrl('http://10.0.0.1/page')).isErr, isTrue);
      expect((await resolver.resolveFromUrl('javascript:alert(1)')).isErr, isTrue);
    });

    test('does not fetch discovered resources eagerly', () async {
      final f = FakeFetcher({
        'https://site.example/p': resp('https://site.example/p', 200,
            body: html, headers: {'content-type': 'text/html'}),
      });
      final r = await MediaLinkResolver(f).resolveFromUrl('https://site.example/p');
      expect(r.isOk, isTrue);
      // Only the page itself was requested; no media/subtitle downloads happened.
      expect(f.requested.length, 1);
    });
  });

  group('MediaActionRouter', () {
    test('requires confirmation before fetching anything', () {
      final magnet = MediaLinkResolver(FakeFetcher({})).resolveFromHtml(
          html: '<a href="magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567">m</a>',
          baseUrl: Uri.parse('https://s.example/p'));
      final routed = MediaActionRouter.route(magnet.resources.first);
      expect(routed.target, RouteTarget.addTorrent);
      expect(routed.requiresConfirmation, isTrue);
    });

    test('routes streams to the player and subtitles to attach', () {
      final hls = MediaActionRouter.route(MediaLinkResolver(FakeFetcher({})).resolveFromHtml(
        html: '<a href="s.m3u8">s</a>', baseUrl: Uri.parse('https://s.example/p')).resources.first);
      expect(hls.target, RouteTarget.player);
      final srt = MediaActionRouter.route(MediaLinkResolver(FakeFetcher({})).resolveFromHtml(
        html: '<a href="s.srt">s</a>', baseUrl: Uri.parse('https://s.example/p')).resources.first);
      expect(srt.target, RouteTarget.attachSubtitle);
    });
  });

  group('WebSandboxPolicy', () {
    test('blocks dangerous navigations and permits normal web pages', () {
      expect(WebSandboxPolicy.allowsNavigation('https://example.com/a'), isTrue);
      expect(WebSandboxPolicy.allowsNavigation('#anchor'), isTrue);
      expect(WebSandboxPolicy.allowsNavigation('javascript:alert(1)'), isFalse);
      expect(WebSandboxPolicy.allowsNavigation('file:///etc/passwd'), isFalse);
      expect(WebSandboxPolicy.allowsNavigation('http://127.0.0.1/x'), isFalse);
    });

    test('default sandbox disables JavaScript and file access', () {
      expect(WebSandboxPolicy.untrusted.javascriptEnabled, isFalse);
      expect(WebSandboxPolicy.untrusted.allowFileAccess, isFalse);
    });
  });
}
