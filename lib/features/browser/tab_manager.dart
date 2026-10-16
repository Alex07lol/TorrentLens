import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/services.dart';
import '../../domain/tabs/browser_tab.dart';
import '../../domain/tabs/tab_set.dart';
import 'tab_restore_service.dart';

/// The one place that owns the tab workspace.
///
/// The logic itself lives in [TabSet] (pure); this class only adds the two
/// things a UI needs — Riverpod state and persistence — plus debounced writes so
/// a burst of navigation callbacks does not hammer SQLite. Every mutation goes
/// through `state = ...`, so no screen can mutate one tab's state from another
/// tab's callback.
class TabManager extends Notifier<TabSet> {
  static const TabRestoreService _restore = TabRestoreService();
  static const Duration persistDebounce = Duration(milliseconds: 350);

  Timer? _persistTimer;
  bool _restored = false;

  /// Diagnostics for the last failed write. Tab persistence is a convenience,
  /// not a correctness requirement, so a failure must never break navigation —
  /// but it is recorded rather than hidden.
  String? lastPersistError;

  @override
  TabSet build() {
    ref.onDispose(() => _persistTimer?.cancel());
    return TabSet.empty.open(BrowserTab.home(TabSet.newTabId()));
  }

  AppServices get _services => ref.read(servicesProvider);

  /// Loads the persisted workspace once, at startup. Safe to call repeatedly.
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final stored = await _services.tabs.load();
      if (stored.isEmpty) {
        await persistNow();
        return;
      }
      state = _restore.toTabSet(_restore.restore(stored));
    } catch (e) {
      // A corrupt workspace must not stop the app from starting; the fresh
      // in-memory workspace stays.
      lastPersistError = '$e';
    }
  }

  Future<void> persistNow() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    try {
      await _services.tabs.saveAll(state.tabs, activeId: state.activeId);
      lastPersistError = null;
    } catch (e) {
      lastPersistError = '$e';
    }
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(persistDebounce, () {
      _persistTimer = null;
      persistNow();
    });
  }

  // ---------------------------------------------------------------- opening

  /// Opens [tab] (or focuses an identical existing tab) and returns the id of
  /// the tab that is now showing that destination.
  String openTab(BrowserTab tab, {bool activate = true}) {
    state = state.open(tab, activate: activate);
    _schedulePersist();
    return state.activeId ?? tab.id;
  }

  /// Explicit "open in a new tab": the source tab keeps the user's attention.
  void openInBackground(BrowserTab tab) {
    state = state.openInBackground(tab);
    _schedulePersist();
  }

  /// Opens [url]. A `file://` URL is a local HTML bundle inside a torrent; the
  /// host then renders it in the sandbox with JavaScript off.
  String openWeb(Uri url, {String? title, bool activate = true}) {
    final location = url.toString();
    final label = url.scheme == 'file'
        ? (url.pathSegments.isEmpty ? 'Offline page' : url.pathSegments.last)
        : (url.host.isEmpty ? location : url.host);
    return openTab(
      _fresh(type: BrowserTabType.web, title: title ?? label, location: location),
      activate: activate,
    );
  }

  String openContent({
    required BrowserTabType type,
    required String location,
    required String title,
    String? contentId,
    bool activate = true,
  }) =>
      openTab(
        _fresh(type: type, title: title, location: location, contentId: contentId),
        activate: activate,
      );

  String openTorrent({required String infoHash, required String title, String? taskId}) =>
      openTab(_fresh(
        type: BrowserTabType.torrent,
        title: title,
        location: infoHash,
        contentId: taskId,
      ));

  /// A tab whose history starts at its opening location, so back/forward work
  /// from the very first page.
  BrowserTab _fresh({
    required BrowserTabType type,
    required String title,
    required String location,
    String? contentId,
  }) {
    final id = TabSet.newTabId();
    final entry = TabHistoryEntry(
      location: location,
      title: title,
      type: type,
      contentId: contentId,
    );
    return BrowserTab(
      id: id,
      type: type,
      title: title,
      location: location,
      contentId: contentId,
      history: type == BrowserTabType.home ? const [] : [entry],
      historyIndex: 0,
      lastVisitedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  String openHomeTab({bool activate = true}) =>
      openTab(BrowserTab.home(TabSet.newTabId()), activate: activate);

  // -------------------------------------------------------------- switching

  void activate(String id) {
    if (state.activeId == id) return;
    state = state.activateTab(id).touch(id);
    _schedulePersist();
  }

  void activateIndex(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    activate(state.tabs[index].id);
  }

  // ---------------------------------------------------------------- closing

  void close(String id) {
    state = state.close(id);
    _schedulePersist();
  }

  void closeActive() {
    final id = state.activeId;
    if (id == null) return;
    close(id);
  }

  void closeAll() {
    state = state.closeAll();
    _schedulePersist();
  }

  void closeOthers(String id) {
    state = state.closeOthers(id);
    _schedulePersist();
  }

  // -------------------------------------------------------------- per-tab state

  void setLoading(String id, bool loading) {
    state = state.setLoading(id, loading);
  }

  void setError(String id, String? message) {
    state = state.setError(id, message);
    _schedulePersist();
  }

  /// Adopts the page's own title, but never lets an empty or placeholder title
  /// erase a good one.
  void setTitle(String id, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    state = state.setTitle(id, trimmed);
    _schedulePersist();
  }

  void setScroll(String id, double offset) => state = state.setScroll(id, offset);

  void navigate({
    required String location,
    required String title,
    BrowserTabType? type,
    String? contentId,
    bool push = true,
    String? tabId,
  }) {
    final id = tabId ?? state.activeId;
    if (id == null) return;
    state = state.navigate(
      id,
      location: location,
      title: title,
      type: type,
      contentId: contentId,
      push: push,
    );
    _schedulePersist();
  }

  void back([String? tabId]) {
    final id = tabId ?? state.activeId;
    if (id == null) return;
    state = state.back(id);
    _schedulePersist();
  }

  void forward([String? tabId]) {
    final id = tabId ?? state.activeId;
    if (id == null) return;
    state = state.forward(id);
    _schedulePersist();
  }

  /// True when the active tab has somewhere to go back to inside itself.
  bool get activeCanGoBack => state.active?.canGoBack ?? false;
}

final tabManagerProvider =
    NotifierProvider<TabManager, TabSet>(TabManager.new);
