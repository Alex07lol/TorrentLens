import 'dart:io';

import '../../domain/security/url_policy.dart';
import '../../domain/tabs/browser_tab.dart';
import '../../domain/tabs/tab_set.dart';

/// Turns persisted tab rows back into a usable workspace.
///
/// Restoring is where a browser-like app usually breaks: the file moved, the
/// torrent was removed, the URL was never valid. Every restored tab is therefore
/// re-validated, and anything that cannot be restored keeps its identity but
/// gains an [BrowserTab.error] describing the problem, so the host renders a
/// recovery screen instead of a blank frame or a crash.
class TabRestoreService {
  /// Kept small and injected so the rules are testable without touching disk.
  final bool Function(String path) fileExists;

  const TabRestoreService({this.fileExists = _defaultFileExists});

  static bool _defaultFileExists(String path) {
    if (path.isEmpty) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// A defensible ceiling: a phone cannot hold an unbounded workspace, and the
  /// rows beyond this are the least recently visited.
  static const int maxRestoredTabs = 20;

  static const String missingFileMessage =
      'The file this tab was showing is no longer available.';
  static const String invalidAddressMessage =
      'This tab’s address is not a valid http(s) page.';

  List<BrowserTab> restore(List<BrowserTab> stored) {
    if (stored.isEmpty) return [BrowserTab.home(TabSet.newTabId())];

    final ordered = [...stored]
      ..sort((a, b) => (b.lastVisitedAtMs ?? 0).compareTo(a.lastVisitedAtMs ?? 0));
    final kept = ordered.take(maxRestoredTabs).toList()
      // Keep the original left-to-right order of the workspace once trimmed.
      ..sort((a, b) => stored.indexOf(a).compareTo(stored.indexOf(b)));

    var activeSeen = false;
    final restored = <BrowserTab>[];
    for (final tab in kept) {
      final wasActive = tab.active && !activeSeen;
      if (wasActive) activeSeen = true;
      final problem = _problem(tab);
      restored.add(tab.copyWith(
        active: wasActive,
        loading: false,
        error: problem,
        clearError: problem == null,
        history: tab.history,
      ));
    }

    if (!activeSeen && restored.isNotEmpty) {
      restored[0] = restored[0].copyWith(active: true);
    }
    return restored;
  }

  String? _problem(BrowserTab tab) {
    switch (tab.type) {
      case BrowserTabType.home:
        return null;
      case BrowserTabType.web:
        if (tab.location.isEmpty) return 'This tab has no address.';
        if (tab.location.startsWith('file:')) {
          final path = Uri.parse(tab.location).toFilePath();
          return fileExists(path) ? null : missingFileMessage;
        }
        return UrlPolicy.evaluate(tab.location, use: UrlUse.navigation).isOk
            ? null
            : invalidAddressMessage;
      case BrowserTabType.torrent:
      case BrowserTabType.subscription:
      case BrowserTabType.cloud:
      case BrowserTabType.explorer:
      case BrowserTabType.media:
        if (tab.location.isEmpty) return 'This tab is missing the content it was showing.';
        return null;
      case BrowserTabType.player:
      case BrowserTabType.epub:
      case BrowserTabType.pdf:
      case BrowserTabType.comic:
      case BrowserTabType.text:
        if (tab.location.isEmpty) return missingFileMessage;
        return fileExists(tab.location) ? null : missingFileMessage;
    }
  }

  /// Rebuilds a [TabSet] from restored tabs, preserving the stored active tab.
  TabSet toTabSet(List<BrowserTab> restored) {
    if (restored.isEmpty) {
      return TabSet.empty.open(BrowserTab.home(TabSet.newTabId()));
    }
    final active = restored.firstWhere((t) => t.active, orElse: () => restored.first);
    return TabSet(
      tabs: [for (final t in restored) t.copyWith(active: t.id == active.id)],
      activeId: active.id,
    );
  }
}
