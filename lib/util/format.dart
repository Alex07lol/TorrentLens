import 'dart:math';

/// Formatting helpers used across the UI. All of them are pure and unit-tested.
class Fmt {
  static String bytes(int value) {
    if (value < 0) return '—';
    if (value < 1024) return '$value B';
    const units = ['KiB', 'MiB', 'GiB', 'TiB'];
    var v = value / 1024.0;
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
  }

  static String speed(int bytesPerSec) => bytesPerSec <= 0 ? '—' : '${bytes(bytesPerSec)}/s';

  static String percent(double fraction) => '${(fraction.clamp(0, 1) * 100).toStringAsFixed(0)}%';

  static String duration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    return '${d.inSeconds}s';
  }

  static String eta(int totalBytes, int downloadedBytes, int bps) {
    if (bps <= 0 || totalBytes <= 0 || downloadedBytes >= totalBytes) return '—';
    final seconds = (totalBytes - downloadedBytes) / bps;
    if (seconds.isInfinite || seconds > 60 * 60 * 24 * 30) return '—';
    return duration(Duration(seconds: seconds.round()));
  }

  static String relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 30) return '${diff.inDays} d ago';
    return '${when.year}-${_two(when.month)}-${_two(when.day)}';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}

/// A small, dependency-free identifier generator (device id, local row ids).
class Ids {
  static final Random _rng = Random.secure();
  static String newId([String prefix = '']) {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return prefix.isEmpty ? hex : '$prefix-$hex';
  }
}
