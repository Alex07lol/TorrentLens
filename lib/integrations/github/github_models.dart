class GitHubAsset {
  final String name;
  final String browserDownloadUrl;
  final int sizeBytes;
  final String? contentType;
  const GitHubAsset({
    required this.name,
    required this.browserDownloadUrl,
    required this.sizeBytes,
    this.contentType,
  });
}

class GitHubRelease {
  final String tagName;
  final String? name;
  final String? body;
  final DateTime? publishedAt;
  final bool prerelease;
  final bool draft;
  final List<GitHubAsset> assets;
  const GitHubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.prerelease,
    required this.draft,
    required this.assets,
  });

  String? get manifestAssetUrl {
    for (final a in assets) {
      final n = a.name.toLowerCase();
      if (n.endsWith('.manifest.json') || n == 'manifest.json') {
        return a.browserDownloadUrl;
      }
    }
    return null;
  }
}
