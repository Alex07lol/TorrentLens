import '../../core/result.dart';

enum ArchiveSafetyError {
  emptyEntryName,
  absolutePath,
  pathTraversal,
  backslashInName,
  driveLetter,
  tooManyEntries,
  entryTooLarge,
  totalTooLarge,
  suspiciousCompressionRatio,
}

/// Guards archive extraction (EPUB, CBZ, CBR, generic zip) against the classic
/// "zip slip" attack and against decompression bombs. A torrent may contain a
/// hostile archive, so every entry name goes through [validateEntryName] before
/// it is ever joined to a destination path.
class ArchiveSafety {
  /// A single uncompressed entry may not exceed this (1 GiB).
  static const int maxEntryBytes = 1 << 30;
  /// The whole archive may not expand past this (8 GiB).
  static const int maxTotalBytes = 8 << 30;
  static const int maxEntries = 100000;
  /// Flag entries whose claimed ratio is absurd (bomb heuristic).
  static const int maxCompressionRatio = 200;

  static Result<String> validateEntryName(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) return const Err(ArchiveSafetyError.emptyEntryName);
    if (name.contains('\\')) return const Err(ArchiveSafetyError.backslashInName);
    if (name.startsWith('/')) return const Err(ArchiveSafetyError.absolutePath);
    if (RegExp(r'^[A-Za-z]:').hasMatch(name)) {
      return const Err(ArchiveSafetyError.driveLetter);
    }
    // Normalise and reject any traversal component after normalisation.
    final parts = <String>[];
    for (final seg in name.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.isEmpty) return const Err(ArchiveSafetyError.pathTraversal);
        parts.removeLast();
        continue;
      }
      parts.add(seg);
    }
    if (parts.isEmpty) return const Err(ArchiveSafetyError.pathTraversal);
    return Ok(parts.join('/'));
  }

  /// Joins a validated entry name to [destination], refusing to escape it.
  static Result<String> safeJoin(String destination, String entryName) {
    final check = validateEntryName(entryName);
    return check.fold(
      (relative) {
        final base = destination.endsWith('/')
            ? destination.substring(0, destination.length - 1)
            : destination;
        return Ok('$base/$relative');
      },
      (e) => Err(e),
    );
  }

  /// Checks aggregate limits for an archive's central directory.
  static Result<void> checkBudget({
    required int entryCount,
    required int totalUncompressed,
    required int totalCompressed,
  }) {
    if (entryCount > maxEntries) return const Err(ArchiveSafetyError.tooManyEntries);
    if (totalUncompressed > maxTotalBytes) {
      return const Err(ArchiveSafetyError.totalTooLarge);
    }
    if (totalCompressed > 0 &&
        totalUncompressed ~/ totalCompressed > maxCompressionRatio) {
      return const Err(ArchiveSafetyError.suspiciousCompressionRatio);
    }
    return const Ok(null);
  }
}
