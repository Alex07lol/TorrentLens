/// Minimal, correct SemVer 2.0.0 implementation (enough for release ordering).
class SemanticVersion implements Comparable<SemanticVersion> {
  final int major;
  final int minor;
  final int patch;
  final List<String> prerelease;
  final List<String> build;

  const SemanticVersion(
    this.major,
    this.minor,
    this.patch, {
    this.prerelease = const [],
    this.build = const [],
  });

  static final _re = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$');

  static SemanticVersion? tryParse(String raw) {
    final m = _re.firstMatch(raw.trim());
    if (m == null) return null;
    return SemanticVersion(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      prerelease: m.group(4)?.split('.').where((e) => e.isNotEmpty).toList() ?? const [],
      build: m.group(5)?.split('.').where((e) => e.isNotEmpty).toList() ?? const [],
    );
  }

  bool get isPrerelease => prerelease.isNotEmpty;

  @override
  int compareTo(SemanticVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // A version with a prerelease has LOWER precedence than one without.
    if (prerelease.isEmpty && other.prerelease.isNotEmpty) return 1;
    if (prerelease.isNotEmpty && other.prerelease.isEmpty) return -1;
    final n = prerelease.length < other.prerelease.length
        ? prerelease.length
        : other.prerelease.length;
    for (var i = 0; i < n; i++) {
      final c = _compareIdentifier(prerelease[i], other.prerelease[i]);
      if (c != 0) return c;
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }

  static int _compareIdentifier(String a, String b) {
    final an = int.tryParse(a);
    final bn = int.tryParse(b);
    if (an != null && bn != null) return an.compareTo(bn);
    if (an != null) return -1; // numeric identifiers sort before alphanumeric
    if (bn != null) return 1;
    return a.compareTo(b);
  }

  bool operator >(SemanticVersion o) => compareTo(o) > 0;
  bool operator <(SemanticVersion o) => compareTo(o) < 0;
  bool operator >=(SemanticVersion o) => compareTo(o) >= 0;
  bool operator <=(SemanticVersion o) => compareTo(o) <= 0;

  @override
  bool operator ==(Object other) =>
      other is SemanticVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, Object.hashAll(prerelease));

  @override
  String toString() {
    final b = StringBuffer('$major.$minor.$patch');
    if (prerelease.isNotEmpty) b.write('-${prerelease.join('.')}');
    if (build.isNotEmpty) b.write('+${build.join('.')}');
    return b.toString();
  }
}
