/// A single timed subtitle cue.
class SubtitleCue {
  final int startMs;
  final int endMs;
  final String text;
  const SubtitleCue({required this.startMs, required this.endMs, required this.text});
}

/// Parses SubRip (`.srt`) and WebVTT (`.vtt`) subtitle files.
///
/// This is what lets TorrentLens show *external* subtitles found next to a
/// video, which the platform player does not do on its own. Parsing is
/// defensive: malformed cues are skipped rather than aborting the track.
class SubtitleTrack {
  final List<SubtitleCue> cues;
  final String format;
  const SubtitleTrack({required this.cues, required this.format});

  static SubtitleTrack parse(String content, {String? formatHint}) {
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final format = (formatHint ?? _detect(normalized)).toLowerCase();
    final cues = format.contains('vtt') ? _parseVtt(normalized) : _parseSrt(normalized);
    cues.sort((a, b) => a.startMs.compareTo(b.startMs));
    return SubtitleTrack(cues: cues, format: format);
  }

  static String _detect(String content) =>
      content.trimLeft().startsWith('WEBVTT') ? 'vtt' : 'srt';

  static List<SubtitleCue> _parseSrt(String content) {
    final cues = <SubtitleCue>[];
    final blocks = content.split(RegExp(r'\n{2,}'));
    final timeRe = RegExp(r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})');
    for (final block in blocks) {
      final lines = block.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) continue;
      final m = lines.map(timeRe.firstMatch).firstWhere((x) => x != null, orElse: () => null);
      if (m == null) continue;
      final start = _ms(m.group(1)!, m.group(2)!, m.group(3)!, m.group(4)!);
      final end = _ms(m.group(5)!, m.group(6)!, m.group(7)!, m.group(8)!);
      final timeLineIndex = lines.indexWhere((l) => timeRe.hasMatch(l));
      final text = lines.skip(timeLineIndex + 1).join('\n').trim();
      if (text.isEmpty) continue;
      cues.add(SubtitleCue(startMs: start, endMs: end, text: _stripTags(text)));
    }
    return cues;
  }

  static List<SubtitleCue> _parseVtt(String content) {
    final cues = <SubtitleCue>[];
    final lines = content.split('\n');
    final timeRe = RegExp(r'(\d{1,2}):(\d{2}):(\d{2})\.(\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})\.(\d{1,3})');
    var i = 0;
    while (i < lines.length) {
      final m = timeRe.firstMatch(lines[i]);
      if (m == null) {
        i++;
        continue;
      }
      final start = _ms(m.group(1)!, m.group(2)!, m.group(3)!, m.group(4)!);
      final end = _ms(m.group(5)!, m.group(6)!, m.group(7)!, m.group(8)!);
      final buffer = <String>[];
      i++;
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        buffer.add(lines[i]);
        i++;
      }
      final text = buffer.join('\n').trim();
      if (text.isNotEmpty) cues.add(SubtitleCue(startMs: start, endMs: end, text: _stripTags(text)));
      i++;
    }
    return cues;
  }

  static int _ms(String h, String m, String s, String frac) {
    final ms = frac.padRight(3, '0').substring(0, 3);
    return int.parse(h) * 3600000 + int.parse(m) * 60000 + int.parse(s) * 1000 + int.parse(ms);
  }

  static String _stripTags(String text) => text.replaceAll(RegExp(r'<[^>]+>'), '').trim();

  /// The cue active at [positionMs], or null.
  SubtitleCue? cueAt(int positionMs) {
    for (final c in cues) {
      if (positionMs >= c.startMs && positionMs <= c.endMs) return c;
    }
    return null;
  }
}
