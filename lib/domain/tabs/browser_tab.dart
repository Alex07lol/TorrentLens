import 'dart:convert';

/// What a tab is currently showing. The type decides which widget hosts the
/// tab's content and which resources it is allowed to hold.
///
/// This is the *durable* description of a tab. Live objects — WebView
/// controllers, players, readers — are never stored here; they are created by
/// [TabContentHost] from this metadata and released when the tab closes.
enum BrowserTabType {
  /// New-tab page: quick actions, no content of its own.
  home,

  /// A web page, remote or a local HTML bundle inside a torrent.
  web,

  /// A torrent task's detail/contents view.
  torrent,

  /// A location in the on-device content explorer.
  explorer,

  /// Video or audio playback.
  player,

  epub,
  pdf,
  comic,
  text,

  /// A discovered media resource that has not been opened yet.
  media,

  /// A GitHub publisher subscription.
  subscription,

  /// A publisher-operated cloud provider screen.
  cloud;

  static BrowserTabType parse(String? raw) => BrowserTabType.values.firstWhere(
        (t) => t.name == raw,
        orElse: () => BrowserTabType.home,
      );

  /// Types whose content owns an expensive native resource (WebView, ExoPlayer)
  /// and therefore count against the live-tab budget.
  bool get holdsLiveResource =>
      this == BrowserTabType.web || this == BrowserTabType.player;

  /// Types that have a real location to validate when restoring.
  bool get isAddressable => this != BrowserTabType.home;

  bool get isReader =>
      this == BrowserTabType.epub ||
      this == BrowserTabType.pdf ||
      this == BrowserTabType.comic ||
      this == BrowserTabType.text;
}

/// One entry in a tab's navigation history — what the back/forward buttons move
/// through. Only metadata is kept: reloading a location is the tab host's job.
class TabHistoryEntry {
  final String location;
  final String title;
  final BrowserTabType type;
  final String? contentId;

  const TabHistoryEntry({
    required this.location,
    required this.title,
    required this.type,
    this.contentId,
  });

  Map<String, Object?> toJson() => {
        'location': location,
        'title': title,
        'type': type.name,
        if (contentId != null) 'contentId': contentId,
      };

  factory TabHistoryEntry.fromJson(Map<String, Object?> json) => TabHistoryEntry(
        location: '${json['location'] ?? ''}',
        title: '${json['title'] ?? ''}',
        type: BrowserTabType.parse(json['type'] as String?),
        contentId: json['contentId'] as String?,
      );

  @override
  String toString() => 'TabHistoryEntry(${type.name}, $location)';
}

/// A single open tab. Instances are immutable: every change goes through
/// [copyWith], which is what makes rapid updates and restores predictable.
class BrowserTab {
  final String id;
  final BrowserTabType type;
  final String title;

  /// Current URL, local path or content identifier. Empty for [BrowserTabType.home].
  final String location;

  final List<TabHistoryEntry> history;

  /// Index into [history] of the current entry.
  final int historyIndex;

  final bool loading;
  final String? error;
  final String? contentId;
  final int? lastVisitedAtMs;
  final double scrollOffset;
  final bool active;

  const BrowserTab({
    required this.id,
    required this.type,
    required this.title,
    this.location = '',
    this.history = const [],
    this.historyIndex = 0,
    this.loading = false,
    this.error,
    this.contentId,
    this.lastVisitedAtMs,
    this.scrollOffset = 0,
    this.active = false,
  });

  factory BrowserTab.home(String id, {String title = 'New tab'}) =>
      BrowserTab(id: id, type: BrowserTabType.home, title: title);

  TabHistoryEntry? get currentEntry {
    if (history.isEmpty) return null;
    final i = historyIndex.clamp(0, history.length - 1);
    return history[i];
  }

  bool get canGoBack => historyIndex > 0 && historyIndex <= history.length;
  bool get canGoForward => historyIndex < history.length - 1;

  BrowserTab copyWith({
    BrowserTabType? type,
    String? title,
    String? location,
    List<TabHistoryEntry>? history,
    int? historyIndex,
    bool? loading,
    String? error,
    bool clearError = false,
    String? contentId,
    int? lastVisitedAtMs,
    double? scrollOffset,
    bool? active,
  }) =>
      BrowserTab(
        id: id,
        type: type ?? this.type,
        title: title ?? this.title,
        location: location ?? this.location,
        history: history ?? this.history,
        historyIndex: historyIndex ?? this.historyIndex,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        contentId: contentId ?? this.contentId,
        lastVisitedAtMs: lastVisitedAtMs ?? this.lastVisitedAtMs,
        scrollOffset: scrollOffset ?? this.scrollOffset,
        active: active ?? this.active,
      );

  Map<String, Object?> toMap({required int sortOrder}) => {
        'id': id,
        'type': type.name,
        'title': title,
        'location': location,
        'history_json': jsonEncode([for (final h in history) h.toJson()]),
        'history_index': historyIndex,
        'content_id': contentId,
        'last_visited_at': lastVisitedAtMs,
        'scroll_offset': scrollOffset,
        'sort_order': sortOrder,
        'is_active': active ? 1 : 0,
        'error': error,
      };

  static BrowserTab fromMap(Map<String, Object?> row) {
    List<TabHistoryEntry> history = const [];
    final raw = row['history_json'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          history = [
            for (final e in decoded)
              if (e is Map) TabHistoryEntry.fromJson(e.cast<String, Object?>()),
          ];
        }
      } catch (_) {
        // A corrupt history blob must not stop the app from starting: the tab
        // is restored with no history rather than crashing.
        history = const [];
      }
    }
    return BrowserTab(
      id: '${row['id']}',
      type: BrowserTabType.parse(row['type'] as String?),
      title: '${row['title'] ?? ''}',
      location: '${row['location'] ?? ''}',
      history: history,
      historyIndex: (row['history_index'] as int?) ?? 0,
      loading: false,
      error: row['error'] as String?,
      contentId: row['content_id'] as String?,
      lastVisitedAtMs: row['last_visited_at'] as int?,
      scrollOffset: ((row['scroll_offset'] as num?) ?? 0).toDouble(),
      active: ((row['is_active'] as int?) ?? 0) == 1,
    );
  }

  @override
  String toString() => 'BrowserTab(${type.name}, "$title", $location)';
}
