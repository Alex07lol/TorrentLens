import 'html_resource_extractor.dart';

/// Statically scans JavaScript *text* for likely media/torrent URLs. It does
/// not execute anything: the app must never run page scripts just to discover
/// links. Anything found here is treated as a candidate, then re-validated by
/// the classifier and the URL policy.
class ScriptResourceAnalyzer {
  /// Quoted strings that look like media/manifest/subtitle files.
  static final _quotedMedia = RegExp(
      r'''["']([^"'\s<>]+?\.(?:m3u8|mpd|mp4|m4v|webm|mkv|mov|mp3|m4a|aac|flac|ogg|opus|srt|vtt|ass|torrent))(?:\?[^"']*)?["']''',
      caseSensitive: false);

  /// Absolute http(s) URLs anywhere in the script.
  static final _absolute = RegExp(r'''["'](https?://[^"'\s<>]+)["']''');

  /// Assignment patterns such as `file: "x.mp4"` / `source: "y.m3u8"`.
  static final _assignment = RegExp(
      r'''(?:file|src|source|url|stream|playlist|video|audio)\s*[:=]\s*["']([^"'\s<>]+)["']''',
      caseSensitive: false);

  static List<DiscoveredLink> extract(String js, {Uri? baseUrl}) {
    final out = <DiscoveredLink>[];
    void add(String? raw, String via) {
      if (raw == null || raw.isEmpty) return;
      final resolved = _resolve(raw, baseUrl);
      if (resolved != null) {
        out.add(DiscoveredLink(url: resolved, sourceTag: 'script', attribute: via));
      }
    }

    for (final m in _quotedMedia.allMatches(js)) {
      add(m.group(1), 'quoted-media');
    }
    for (final m in _absolute.allMatches(js)) {
      add(m.group(1), 'absolute-url');
    }
    for (final m in _assignment.allMatches(js)) {
      add(m.group(1), 'assignment');
    }
    return out;
  }

  static String? _resolve(String raw, Uri? base) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    if (uri.hasScheme) {
      final scheme = uri.scheme.toLowerCase();
      return (scheme == 'http' || scheme == 'https' || scheme == 'magnet') ? raw : null;
    }
    if (base == null) return null;
    return base.resolve(raw).toString();
  }
}
