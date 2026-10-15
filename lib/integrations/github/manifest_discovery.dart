import 'github_models.dart';

/// Explicit manifest discovery.
///
/// We do **not** guess: a manifest must be an asset whose name matches one of
/// the documented patterns. This keeps the app from silently treating an
/// unrelated release asset (an APK, an archive, a checksum) as a manifest.
class ManifestDiscovery {
  /// Documented asset names, most specific first.
  static const List<String> candidateSuffixes = [
    '.manifest.json',
    'torrentlens.manifest.json',
    'source.manifest.json',
    'manifest.json',
  ];

  /// Returns the manifest asset for a release, or null when the release does
  /// not publish one.
  static GitHubAsset? findManifestAsset(GitHubRelease release) {
    final scored = <MapEntry<int, GitHubAsset>>[];
    for (final a in release.assets) {
      final n = a.name.toLowerCase();
      var score = -1;
      for (var i = 0; i < candidateSuffixes.length; i++) {
        if (n == candidateSuffixes[i] || n.endsWith(candidateSuffixes[i])) {
          score = i;
          break;
        }
      }
      if (score >= 0) scored.add(MapEntry(score, a));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => a.key.compareTo(b.key));
    return scored.first.value;
  }

  /// Picks the newest non-draft, non-prerelease release that has a manifest.
  static GitHubRelease? newestWithManifest(List<GitHubRelease> releases) {
    final usable = releases
        .where((r) => !r.draft && !r.prerelease && findManifestAsset(r) != null)
        .toList();
    if (usable.isEmpty) return null;
    usable.sort((a, b) {
      final da = a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
    return usable.first;
  }
}
