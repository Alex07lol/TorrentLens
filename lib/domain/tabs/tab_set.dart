import 'browser_tab.dart';

/// The tab workspace: an ordered list of tabs plus which one is active.
///
/// Every operation is a pure function over immutable data, so tab behaviour
/// (open, switch, close, back/forward, dedupe, resource limits) is unit-tested
/// without a widget tree, a database or a device. The UI and the persistence
/// layer both go through these methods, which is what keeps them agreeing.
class TabSet {
  final List<BrowserTab> tabs;
  final String? activeId;

  const TabSet({required this.tabs, required this.activeId});

  static const TabSet empty = TabSet(tabs: [], activeId: null);

  /// How many tabs may hold a live native resource (WebView, player) at once.
  /// Inactive tabs beyond this are evicted and reloaded when revisited.
  static const int defaultMaxLiveTabs = 6;

  bool get isEmpty => tabs.isEmpty;
  int get length => tabs.length;

  BrowserTab? get active {
    if (tabs.isEmpty) return null;
    for (final t in tabs) {
      if (t.id == activeId) return t;
    }
    return tabs.first;
  }

  BrowserTab? byId(String? id) {
    if (id == null) return null;
    for (final t in tabs) {
      if (t.id == id) return t;
    }
    return null;
  }

  int indexOf(String id) => tabs.indexWhere((t) => t.id == id);

  /// A tab showing exactly the same thing, if one is already open.
  ///
  /// Opening the same URL twice in a row must focus the existing tab instead of
  /// stacking duplicates — this is the guard against repeated navigation
  /// callbacks creating a new tab per rebuild.
  /// A strictly increasing visit timestamp.
  ///
  /// Wall-clock milliseconds can repeat within a single frame, and the tab
  /// budget decides what to evict from these stamps — so they must never tie.
  static int _lastStamp = 0;
  static int _nowMs() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastStamp = now > _lastStamp ? now : _lastStamp + 1;
    return _lastStamp;
  }

  BrowserTab? _duplicateOf(BrowserTab candidate) {
    if (candidate.type == BrowserTabType.home) {
      for (final t in tabs) {
        if (t.type == BrowserTabType.home) return t;
      }
      return null;
    }
    if (candidate.location.isEmpty) return null;
    for (final t in tabs) {
      if (t.type == candidate.type && t.location == candidate.location) return t;
    }
    // A reader/player opened from the same file counts as the same destination.
    if (candidate.type.isReader && candidate.location.isNotEmpty) {
      for (final t in tabs) {
        if (t.type.isReader && t.location == candidate.location) return t;
      }
    }
    return null;
  }

  /// Opens [tab], or focuses an existing tab that shows the same destination.
  TabSet open(BrowserTab tab, {bool activate = true}) {
    final existing = _duplicateOf(tab);
    if (existing != null) {
      return activate ? activateTab(existing.id) : this;
    }
    return _withTab(tab, activate: activate);
  }

  /// Opens the same destination as [opened], but never focuses it: used by
  /// explicit "open in new tab" so the source page keeps the user's attention.
  TabSet openInBackground(BrowserTab tab) {
    final existing = _duplicateOf(tab);
    if (existing != null) return this;
    return _withTab(tab, activate: false);
  }

  TabSet _withTab(BrowserTab tab, {required bool activate}) {
    final stamped = tab.copyWith(
      active: activate,
      lastVisitedAtMs: tab.lastVisitedAtMs ?? _nowMs(),
    );
    final next = [
      for (final t in tabs) activate ? t.copyWith(active: false) : t,
      stamped,
    ];
    return TabSet(tabs: next, activeId: activate ? tab.id : (activeId ?? tab.id));
  }

  /// Replaces a tab that is already in the set (used when a caller pre-built it
  /// with an id, e.g. the restore path).
  TabSet merge(BrowserTab tab) {
    final i = indexOf(tab.id);
    if (i < 0) return this;
    final next = [...tabs]..[i] = tab;
    return TabSet(tabs: next, activeId: activeId);
  }

  TabSet activateTab(String? id) {
    if (id == null || indexOf(id) < 0) return this;
    return TabSet(
      tabs: [
        for (final t in tabs) t.copyWith(active: t.id == id),
      ],
      activeId: id,
    );
  }

  /// Closes [id] and moves to a sensible neighbour: the tab to its left, else
  /// the one to its right. Closing the last tab leaves a fresh new-tab page so
  /// the workspace is never blank. Files and torrent tasks are untouched.
  TabSet close(String id) {
    final i = indexOf(id);
    if (i < 0) return this;
    final remaining = [...tabs]..removeAt(i);
    if (remaining.isEmpty) return TabSet.empty.open(BrowserTab.home(_freshId()));
    if (activeId != id) return TabSet(tabs: remaining, activeId: activeId);
    final neighbour = remaining[i > 0 ? i - 1 : 0];
    return TabSet(
      tabs: [for (final t in remaining) t.copyWith(active: t.id == neighbour.id)],
      activeId: neighbour.id,
    );
  }

  TabSet closeAll() => TabSet.empty.open(BrowserTab.home(_freshId()));

  TabSet closeOthers(String id) {
    final keep = byId(id);
    if (keep == null) return this;
    return TabSet(tabs: [keep.copyWith(active: true)], activeId: id);
  }

  /// Applies a change to one tab and only that tab. Every state update (loading,
  /// error, title, scroll) goes through here, so one tab's spinner can never
  /// overwrite another's.
  TabSet updateTab(String id, BrowserTab Function(BrowserTab tab) change) {
    final i = indexOf(id);
    if (i < 0) return this;
    final next = [...tabs]..[i] = change(tabs[i]);
    return TabSet(tabs: next, activeId: activeId);
  }

  TabSet setLoading(String id, bool loading) =>
      updateTab(id, (t) => t.copyWith(loading: loading, clearError: loading));

  TabSet setError(String id, String? message) => updateTab(
        id,
        (t) => t.copyWith(
          loading: false,
          error: message,
          clearError: message == null,
          lastVisitedAtMs: _nowMs(),
        ),
      );

  TabSet setTitle(String id, String title) =>
      updateTab(id, (t) => t.title == title ? t : t.copyWith(title: title));

  TabSet touch(String id) => updateTab(id, (t) => t.copyWith(lastVisitedAtMs: _nowMs()));

  /// Moves a tab's current location, with real browser history semantics:
  /// pushing truncates any forward entries.
  TabSet navigate(
    String id, {
    required String location,
    required String title,
    BrowserTabType? type,
    String? contentId,
    bool push = true,
  }) =>
      updateTab(id, (tab) {
        final entry = TabHistoryEntry(
          location: location,
          title: title,
          type: type ?? tab.type,
          contentId: contentId,
        );
        final history = [...tab.history];
        int index;
        if (!push) {
          if (history.isEmpty) {
            history.add(entry);
            index = 0;
          } else {
            index = tab.historyIndex.clamp(0, history.length - 1);
            history[index] = entry;
          }
        } else {
          final keep = history.take(tab.historyIndex.clamp(0, history.length) + 1).toList();
          keep.add(entry);
          history
            ..clear()
            ..addAll(keep);
          index = history.length - 1;
        }
        return tab.copyWith(
          type: entry.type,
          location: location,
          title: title,
          history: history,
          historyIndex: index,
          contentId: contentId,
          loading: false,
          clearError: true,
          lastVisitedAtMs: _nowMs(),
        );
      });

  TabSet back(String id) => updateTab(id, (tab) {
        if (!tab.canGoBack) return tab;
        final i = (tab.historyIndex - 1).clamp(0, tab.history.length - 1);
        final entry = tab.history[i];
        return tab.copyWith(
          historyIndex: i,
          type: entry.type,
          location: entry.location,
          title: entry.title,
          contentId: entry.contentId,
          loading: false,
          clearError: true,
        );
      });

  TabSet forward(String id) => updateTab(id, (tab) {
        if (!tab.canGoForward) return tab;
        final i = (tab.historyIndex + 1).clamp(0, tab.history.length - 1);
        final entry = tab.history[i];
        return tab.copyWith(
          historyIndex: i,
          type: entry.type,
          location: entry.location,
          title: entry.title,
          contentId: entry.contentId,
          loading: false,
          clearError: true,
        );
      });

  TabSet setScroll(String id, double offset) =>
      updateTab(id, (t) => t.copyWith(scrollOffset: offset));

  /// Ids of the tabs that may keep a native resource alive right now: the active
  /// tab plus the most recently visited ones that hold WebViews or players.
  /// Everything else is evicted and rebuilt on demand.
  List<String> liveIds({int limit = defaultMaxLiveTabs}) {
    final candidates = tabs.where((t) => t.type.holdsLiveResource).toList()
      ..sort((a, b) => (b.lastVisitedAtMs ?? 0).compareTo(a.lastVisitedAtMs ?? 0));
    final ids = <String>[];
    final activeTab = active;
    if (activeTab != null) ids.add(activeTab.id);
    for (final t in candidates) {
      if (ids.length >= limit) break;
      if (!ids.contains(t.id)) ids.add(t.id);
    }
    return ids;
  }

  /// Tabs in most-recently-used order, for the "recent tabs" switcher.
  List<BrowserTab> get byRecency {
    final sorted = [...tabs]
      ..sort((a, b) => (b.lastVisitedAtMs ?? 0).compareTo(a.lastVisitedAtMs ?? 0));
    return sorted;
  }

  static int _counter = 0;
  static String _freshId() {
    _counter++;
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'tab-$micros-$_counter';
  }

  /// Generates a new, unique tab id.
  static String newTabId() => _freshId();

  @override
  String toString() => 'TabSet(${tabs.length} tabs, active=$activeId)';
}
