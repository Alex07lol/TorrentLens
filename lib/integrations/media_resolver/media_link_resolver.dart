import '../../core/result.dart';
import '../../domain/media/media_classifier.dart';
import '../../domain/media/media_resource.dart';
import '../../domain/security/url_policy.dart';
import 'css_resource_extractor.dart';
import 'html_resource_extractor.dart';
import 'http_fetcher.dart';
import 'redirect_resolver.dart';
import 'script_resource_analyzer.dart';

class LinkResolutionResult {
  final List<MediaResource> resources;
  final List<String> warnings;
  final int checkedLinks;
  final Uri? pageUrl;
  const LinkResolutionResult({
    required this.resources,
    required this.checkedLinks,
    this.warnings = const [],
    this.pageUrl,
  });

  bool get isEmpty => resources.isEmpty;
}

/// Orchestrates discovery: static extraction from HTML, CSS and (optionally)
/// script text, then classification. It never executes scripts and never
/// downloads the resources it finds — the user decides what to open.
class MediaLinkResolver {
  final HttpFetcher fetcher;
  final int maxResources;
  final int maxFetchBytes;
  final int maxScriptScanChars;

  const MediaLinkResolver(
    this.fetcher, {
    this.maxResources = 200,
    this.maxFetchBytes = 512 * 1024,
    this.maxScriptScanChars = 256 * 1024,
  });

  /// Classifies links already available locally (e.g. from a downloaded file).
  LinkResolutionResult resolveFromHtml({
    required String html,
    required Uri baseUrl,
    String? css,
    bool scanScriptText = true,
  }) {
    final links = <DiscoveredLink>[
      ...HtmlResourceExtractor.extract(html, baseUrl: baseUrl),
      if (css != null && css.isNotEmpty)
        ...CssResourceExtractor.extract(css, stylesheetUrl: baseUrl),
      if (scanScriptText)
        ...ScriptResourceAnalyzer.extract(
            html.length > maxScriptScanChars ? html.substring(0, maxScriptScanChars) : html,
            baseUrl: baseUrl),
    ];
    return _classify(links, baseUrl.toString());
  }

  /// Fetches [rawUrl] (validating every redirect hop) and resolves its links.
  Future<Result<LinkResolutionResult>> resolveFromUrl(String rawUrl) async {
    final validated = UrlPolicy.evaluate(rawUrl, use: UrlUse.fetch);
    if (validated.isErr) return Err(validated.errorOrNull()!);
    final start = validated.valueOrNull!;

    final redirect = RedirectResolver(fetcher);
    final res = await redirect.resolve(start, maxBytes: maxFetchBytes);
    if (res.isErr) return Err(res.errorOrNull()!);
    final r = res.valueOrNull!;
    if (r.statusCode >= 400) {
      return Err('HTTP ${r.statusCode} fetching $rawUrl');
    }

    // Only parse text-ish responses.
    final ct = r.response.contentType?.toLowerCase() ?? '';
    if (ct.isNotEmpty &&
        !ct.contains('html') &&
        !ct.contains('xml') &&
        !ct.contains('text') &&
        !ct.contains('json') &&
        !ct.contains('javascript')) {
      return Ok(LinkResolutionResult(
        resources: [
          MediaClassifier.classify(
            url: r.finalUrl.toString(),
            mimeType: ct,
            sourcePageUrl: r.finalUrl.toString(),
          ),
        ],
        checkedLinks: 1,
        warnings: ['Response was not HTML; classified the response itself.'],
        pageUrl: r.finalUrl,
      ));
    }

    final result = resolveFromHtml(html: r.response.body, baseUrl: r.finalUrl);
    return Ok(LinkResolutionResult(
      resources: result.resources,
      checkedLinks: result.checkedLinks,
      warnings: [
        ...result.warnings,
        if (r.response.truncated) 'Response was truncated at $maxFetchBytes bytes; '
            'some links may be missing.',
      ],
      pageUrl: r.finalUrl,
    ));
  }

  LinkResolutionResult _classify(List<DiscoveredLink> links, String pageUrl) {
    final warnings = <String>[];
    final seen = <String>{};
    final resources = <MediaResource>[];

    for (final l in links) {
      if (resources.length >= maxResources) {
        warnings.add('Stopped after $maxResources resources.');
        break;
      }
      if (!seen.add(l.url)) continue;

      // Validate before classifying so unsafe schemes never become actions.
      final isMagnet = l.url.startsWith('magnet:');
      if (!isMagnet) {
        final ok = UrlPolicy.evaluate(l.url, use: UrlUse.navigation);
        if (ok.isErr) continue;
      }
      final r = MediaClassifier.classify(
        url: l.url,
        title: l.title,
        sourcePageUrl: pageUrl,
      );
      // Web pages discovered as anchors aren't interesting on their own unless
      // they are the page itself; keep them out of the panel noise.
      if (r.kind == MediaKind.webPage && l.sourceTag == 'a') continue;
      resources.add(r);
    }
    return LinkResolutionResult(
      resources: resources,
      checkedLinks: links.length,
      warnings: warnings,
      pageUrl: Uri.tryParse(pageUrl),
    );
  }
}
