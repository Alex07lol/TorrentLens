import 'html_resource_extractor.dart';

/// Extracts `url(...)` and `@import` references from CSS. Relative references
/// resolve against the stylesheet's own URL, not the page's.
class CssResourceExtractor {
  static final _urlRe = RegExp(r'''url\(\s*(?:"([^"]*)"|'([^']*)'|([^)\s]*))\s*\)''');
  static final _importRe = RegExp(r'''@import\s+(?:url\(\s*)?["']([^"']+)["']''');

  static List<DiscoveredLink> extract(String css, {Uri? stylesheetUrl}) {
    final out = <DiscoveredLink>[];
    for (final m in _urlRe.allMatches(css)) {
      final raw = (m.group(1) ?? m.group(2) ?? m.group(3) ?? '').trim();
      if (raw.isEmpty || raw.startsWith('data:')) continue;
      final resolved = _resolve(raw, stylesheetUrl);
      if (resolved != null) {
        out.add(DiscoveredLink(url: resolved, sourceTag: 'css', attribute: 'url()'));
      }
    }
    for (final m in _importRe.allMatches(css)) {
      final resolved = _resolve(m.group(1)!.trim(), stylesheetUrl);
      if (resolved != null) {
        out.add(DiscoveredLink(url: resolved, sourceTag: 'css', attribute: '@import'));
      }
    }
    return out;
  }

  static String? _resolve(String raw, Uri? base) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    if (uri.hasScheme) return raw;
    if (base == null) return null;
    return base.resolve(raw).toString();
  }
}
