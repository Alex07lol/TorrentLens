import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// A link found in markup, before classification.
class DiscoveredLink {
  final String url;
  final String? title;
  final String sourceTag;
  final String attribute;
  const DiscoveredLink({
    required this.url,
    required this.sourceTag,
    required this.attribute,
    this.title,
  });
}

/// Extracts candidate resource references from HTML using *static* parsing
/// only. It never executes page scripts; JavaScript-produced links are handled
/// separately by [ScriptResourceAnalyzer] or a restricted WebView.
class HtmlResourceExtractor {
  /// Attribute map: element selector -> attributes that can carry a URL.
  static const Map<String, List<String>> _rules = {
    'a': ['href'],
    'img': ['src', 'data-src', 'data-original'],
    'video': ['src', 'poster'],
    'audio': ['src'],
    'source': ['src'],
    'track': ['src'],
    'iframe': ['src'],
    'embed': ['src'],
    'object': ['data'],
    'link': ['href'],
    'script': ['src'],
  };

  static List<DiscoveredLink> extract(String html, {Uri? baseUrl}) {
    final out = <DiscoveredLink>[];
    if (html.trim().isEmpty) return out;

    dom.Document doc;
    try {
      doc = html_parser.parse(html);
    } catch (_) {
      return out; // malformed input yields nothing rather than throwing
    }

    for (final entry in _rules.entries) {
      for (final el in doc.querySelectorAll(entry.key)) {
        for (final attr in entry.value) {
          final raw = el.attributes[attr];
          if (raw == null || raw.trim().isEmpty) continue;
          final resolved = _resolve(raw.trim(), baseUrl);
          if (resolved == null) continue;
          out.add(DiscoveredLink(
            url: resolved,
            sourceTag: entry.key,
            attribute: attr,
            title: _titleOf(el),
          ));
        }
      }
      // srcset is a list of candidates
      if (entry.key == 'img' || entry.key == 'source') {
        for (final el in doc.querySelectorAll(entry.key)) {
          final srcset = el.attributes['srcset'];
          if (srcset == null) continue;
          for (final part in srcset.split(',')) {
            final url = part.trim().split(RegExp(r'\s+')).first;
            final resolved = _resolve(url, baseUrl);
            if (resolved != null) {
              out.add(DiscoveredLink(url: resolved, sourceTag: entry.key, attribute: 'srcset'));
            }
          }
        }
      }
    }

    // Data attributes that frequently hold media/torrent targets.
    for (final el in doc.querySelectorAll('*')) {
      for (final entry in el.attributes.entries) {
        final name = entry.key.toString();
        if (!name.startsWith('data-')) continue;
        final trimmed = entry.value.trim();
        if (!trimmed.startsWith('magnet:') &&
            !trimmed.startsWith('http://') &&
            !trimmed.startsWith('https://')) {
          continue;
        }
        final resolved =
            trimmed.startsWith('magnet:') ? trimmed : _resolve(trimmed, baseUrl);
        if (resolved != null) {
          out.add(DiscoveredLink(
              url: resolved, sourceTag: el.localName ?? '?', attribute: name));
        }
      }
    }

    return _dedupe(out);
  }

  static String? _titleOf(dom.Element el) {
    final t = el.attributes['title'] ?? el.attributes['alt'];
    if (t != null && t.trim().isNotEmpty) return t.trim();
    final text = el.text.trim();
    if (text.isNotEmpty && text.length <= 120) return text;
    return null;
  }

  static String? _resolve(String raw, Uri? baseUrl) {
    if (raw.startsWith('magnet:')) return raw;
    if (raw.startsWith('//')) {
      return baseUrl == null ? null : '${baseUrl.scheme}:$raw';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    if (uri.hasScheme) {
      // Only these schemes can ever become a routed action; javascript:, data:,
      // file:, blob:, intent: etc. are dropped at the source.
      final scheme = uri.scheme.toLowerCase();
      return (scheme == 'http' || scheme == 'https' || scheme == 'magnet') ? raw : null;
    }
    if (baseUrl == null) return null;
    return baseUrl.resolve(raw).toString();
  }

  static List<DiscoveredLink> _dedupe(List<DiscoveredLink> links) {
    final seen = <String>{};
    final out = <DiscoveredLink>[];
    for (final l in links) {
      if (seen.add(l.url)) out.add(l);
    }
    return out;
  }
}
