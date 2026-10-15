/// A parsed GitHub repository / release reference.
class GitHubRef {
  final String owner;
  final String repo;
  /// `tag` and `release` are set when the URL pointed at a specific release.
  final String? tag;
  final bool isRelease;

  const GitHubRef({
    required this.owner,
    required this.repo,
    this.tag,
    this.isRelease = false,
  });

  String get fullName => '$owner/$repo';

  /// GitHub login rules: alphanumerics and single hyphens, 1..39 chars.
  static const _githubReserved = {
    'about', 'pricing', 'features', 'enterprise', 'security', 'blog',
    'contact', 'login', 'signup', 'settings', 'explore', 'topics', 'trending',
    'collections', 'sponsors', 'apps', 'marketplace', 'new', 'organizations',
    'users', 'notifications', 'issues', 'pulls', 'codespaces', 'discussions',
  };

  static bool isValidOwner(String s) {
    if (s.isEmpty || s.length > 39) return false;
    if (_githubReserved.contains(s.toLowerCase())) return false;
    if (s.startsWith('-') || s.endsWith('-')) return false;
    if (s.contains('--')) return false;
    return RegExp(r'^[A-Za-z0-9-]+$').hasMatch(s);
  }

  static bool isValidRepo(String s) {
    if (s.isEmpty || s.length > 100) return false;
    if (s == '.' || s == '..') return false;
    return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(s);
  }

  /// Parses `https://github.com/owner/repo`, `.../releases`, `.../releases/tag/v1.2.3`,
  /// `.../releases/latest`, or a bare `owner/repo` shorthand.
  static GitHubRef? tryParse(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;

    // bare owner/repo shorthand
    if (!s.contains('://')) {
      final parts = s.split('/');
      if (parts.length == 2 && isValidOwner(parts[0]) && isValidRepo(parts[1])) {
        return GitHubRef(owner: parts[0], repo: parts[1]);
      }
      return null;
    }

    final uri = Uri.tryParse(s);
    if (uri == null) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    if (!(uri.host == 'github.com' || uri.host == 'www.github.com')) return null;

    final seg = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    if (seg.length < 2) return null;
    final owner = seg[0];
    final repo = seg[1].endsWith('.git')
        ? seg[1].substring(0, seg[1].length - 4)
        : seg[1];
    if (!isValidOwner(owner) || !isValidRepo(repo)) return null;

    if (seg.length >= 4 && seg[2] == 'releases') {
      if (seg[3] == 'tag' && seg.length >= 5) {
        return GitHubRef(owner: owner, repo: repo, tag: seg[4], isRelease: true);
      }
      if (seg[3] == 'latest') {
        return GitHubRef(owner: owner, repo: repo, tag: 'latest', isRelease: true);
      }
      return GitHubRef(owner: owner, repo: repo, isRelease: true);
    }
    return GitHubRef(owner: owner, repo: repo);
  }
}
