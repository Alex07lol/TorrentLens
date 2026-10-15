/// A GitHub publisher subscription.
class Subscription {
  final String id;
  final String publisherId;
  final String owner;
  final String repo;
  final String title;
  final String? installedVersion;
  final String? latestVersion;
  final String trustStatus;
  final int? lastCheckedAtMs;
  final int checkIntervalHours;
  final bool autoDownload;
  final String? manifestUrl;
  final String? magnetUri;

  const Subscription({
    required this.id,
    required this.publisherId,
    required this.owner,
    required this.repo,
    required this.title,
    this.installedVersion,
    this.latestVersion,
    this.trustStatus = 'unsigned',
    this.lastCheckedAtMs,
    this.checkIntervalHours = 24,
    this.autoDownload = false,
    this.manifestUrl,
    this.magnetUri,
  });

  String get fullName => '$owner/$repo';

  bool get isCheckDue {
    if (lastCheckedAtMs == null) return true;
    final due = lastCheckedAtMs! + checkIntervalHours * 3600 * 1000;
    return DateTime.now().millisecondsSinceEpoch >= due;
  }

  Subscription copyWith({
    String? latestVersion,
    String? installedVersion,
    String? trustStatus,
    int? lastCheckedAtMs,
    bool? autoDownload,
    int? checkIntervalHours,
    String? manifestUrl,
    String? magnetUri,
  }) =>
      Subscription(
        id: id,
        publisherId: publisherId,
        owner: owner,
        repo: repo,
        title: title,
        installedVersion: installedVersion ?? this.installedVersion,
        latestVersion: latestVersion ?? this.latestVersion,
        trustStatus: trustStatus ?? this.trustStatus,
        lastCheckedAtMs: lastCheckedAtMs ?? this.lastCheckedAtMs,
        checkIntervalHours: checkIntervalHours ?? this.checkIntervalHours,
        autoDownload: autoDownload ?? this.autoDownload,
        manifestUrl: manifestUrl ?? this.manifestUrl,
        magnetUri: magnetUri ?? this.magnetUri,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'publisher_id': publisherId,
        'owner': owner,
        'repo': repo,
        'title': title,
        'installed_version': installedVersion,
        'latest_version': latestVersion,
        'trust_status': trustStatus,
        'last_checked_at': lastCheckedAtMs,
        'check_interval_hours': checkIntervalHours,
        'auto_download': autoDownload ? 1 : 0,
        'manifest_url': manifestUrl,
        'magnet_uri': magnetUri,
      };

  static Subscription fromMap(Map<String, Object?> m) => Subscription(
        id: '${m['id']}',
        publisherId: '${m['publisher_id']}',
        owner: '${m['owner']}',
        repo: '${m['repo']}',
        title: '${m['title']}',
        installedVersion: m['installed_version'] as String?,
        latestVersion: m['latest_version'] as String?,
        trustStatus: '${m['trust_status'] ?? 'unsigned'}',
        lastCheckedAtMs: m['last_checked_at'] as int?,
        checkIntervalHours: (m['check_interval_hours'] as int?) ?? 24,
        autoDownload: (m['auto_download'] as int? ?? 0) == 1,
        manifestUrl: m['manifest_url'] as String?,
        magnetUri: m['magnet_uri'] as String?,
      );
}
