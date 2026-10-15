import 'dart:convert';
import 'package:xml/xml.dart';

enum StreamFormat { hls, dash }

class StreamVariant {
  final String url;
  final int? bandwidthBps;
  final String? resolution;
  final String? codecs;
  const StreamVariant({required this.url, this.bandwidthBps, this.resolution, this.codecs});
}

class StreamManifest {
  final StreamFormat format;
  final bool isMaster;
  final List<StreamVariant> variants;
  final int? durationSeconds;
  /// Subtitle/audio groups declared in the manifest, surfaced in the player.
  final Map<String, String> subtitleTracks;

  const StreamManifest({
    required this.format,
    required this.isMaster,
    required this.variants,
    this.durationSeconds,
    this.subtitleTracks = const {},
  });
}

/// Parses HLS (`.m3u8`) and DASH (`.mpd`) manifests from raw text. Parsing is
/// defensive: it never trusts a manifest to be well-formed and returns null
/// rather than throwing on hostile input.
class StreamManifestParser {
  static StreamManifest? tryParse(String content, {String? urlHint}) {
    final trimmed = content.trimLeft();
    if (trimmed.startsWith('#EXTM3U')) return _parseHls(content, urlHint);
    if (trimmed.startsWith('<') || trimmed.toLowerCase().contains('<mpd')) {
      return _parseDash(content, urlHint);
    }
    return null;
  }

  static StreamManifest _parseHls(String content, String? base) {
    final lines = const LineSplitter().convert(content);
    final variants = <StreamVariant>[];
    final subs = <String, String>{};
    var isMaster = false;
    int? duration;

    // HLS durations are the sum of #EXTINF values in a media playlist.
    var sum = 0.0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        isMaster = true;
        final attrs = _parseHlsAttrs(line.substring('#EXT-X-STREAM-INF:'.length));
        int? bandwidth;
        if (attrs['BANDWIDTH'] != null) bandwidth = int.tryParse(attrs['BANDWIDTH']!);
        String? next;
        for (var j = i + 1; j < lines.length; j++) {
          final cand = lines[j].trim();
          if (cand.isEmpty || cand.startsWith('#')) continue;
          next = cand;
          break;
        }
        if (next != null) {
          variants.add(StreamVariant(
            url: _resolve(next, base),
            bandwidthBps: bandwidth,
            resolution: attrs['RESOLUTION'],
            codecs: attrs['CODECS'],
          ));
        }
      } else if (line.startsWith('#EXT-X-MEDIA:')) {
        final attrs = _parseHlsAttrs(line.substring('#EXT-X-MEDIA:'.length));
        if (attrs['TYPE'] == 'SUBTITLES' && attrs['URI'] != null) {
          subs[attrs['NAME'] ?? attrs['GROUP-ID'] ?? 'subtitle'] =
              _resolve(attrs['URI']!, base);
        }
      } else if (line.startsWith('#EXT-X-VERSION:')) {
        // Informational for this parser; the variant/segment data is what we use.
      } else if (line.startsWith('#EXTINF:')) {
        final v = line
            .substring('#EXTINF:'.length)
            .split(',')
            .first
            .trim();
        sum += double.tryParse(v) ?? 0;
      }
    }
    if (sum > 0) duration = sum.round();

    return StreamManifest(
      format: StreamFormat.hls,
      isMaster: isMaster,
      variants: variants,
      durationSeconds: duration,
      subtitleTracks: subs,
    );
  }

  static Map<String, String> _parseHlsAttrs(String input) {
    final out = <String, String>{};
    // Attribute lists can contain quoted values with commas; split carefully.
    final re = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');
    for (final m in re.allMatches(input)) {
      var v = m.group(2) ?? '';
      if (v.startsWith('"') && v.endsWith('"') && v.length >= 2) {
        v = v.substring(1, v.length - 1);
      }
      out[m.group(1)!] = v;
    }
    return out;
  }

  static StreamManifest? _parseDash(String content, String? base) {
    try {
      final doc = XmlDocument.parse(content);
      final mpd = doc.rootElement;
      if (mpd.name.local.toLowerCase() != 'mpd') return null;
      int? duration;
      final durAttr = mpd.getAttribute('mediaPresentationDuration');
      if (durAttr != null) duration = _parseIso8601Duration(durAttr);

      final variants = <StreamVariant>[];
      for (final set in doc.findAllElements('AdaptationSet')) {
        for (final rep in set.findAllElements('Representation')) {
          final id = rep.getAttribute('id') ?? rep.getAttribute('bandwidth') ?? 'rep';
          variants.add(StreamVariant(
            url: _resolve('rep-$id', base),
            bandwidthBps: int.tryParse(rep.getAttribute('bandwidth') ?? ''),
            resolution: (rep.getAttribute('width') != null &&
                    rep.getAttribute('height') != null)
                ? '${rep.getAttribute('width')}x${rep.getAttribute('height')}'
                : null,
            codecs: rep.getAttribute('codecs'),
          ));
        }
      }
      return StreamManifest(
        format: StreamFormat.dash,
        isMaster: true,
        variants: variants,
        durationSeconds: duration,
      );
    } catch (_) {
      return null;
    }
  }

  /// ISO-8601 durations like `PT1H2M3.5S`.
  static int? _parseIso8601Duration(String s) {
    final m = RegExp(r'^P(?:(\d+)D)?T(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?$').firstMatch(s);
    if (m == null) return null;
    final d = int.tryParse(m.group(1) ?? '') ?? 0;
    final h = int.tryParse(m.group(2) ?? '') ?? 0;
    final min = int.tryParse(m.group(3) ?? '') ?? 0;
    final sec = double.tryParse(m.group(4) ?? '')?.round() ?? 0;
    return d * 86400 + h * 3600 + min * 60 + sec;
  }

  static String _resolve(String ref, String? base) {
    if (base == null) return ref;
    final b = Uri.tryParse(base);
    if (b == null) return ref;
    return b.resolve(ref).toString();
  }
}
