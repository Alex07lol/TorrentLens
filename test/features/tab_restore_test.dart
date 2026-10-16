import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/domain/tabs/browser_tab.dart';
import 'package:torrentlens/features/browser/tab_restore_service.dart';

void main() {
  const service = TabRestoreService(fileExists: _onlyExisting);

  group('TabRestoreService', () {
    test('an empty workspace restores to one blank tab', () {
      final restored = service.restore(const []);
      expect(restored.length, 1);
      expect(restored.single.type, BrowserTabType.home);
      expect(service.toTabSet(restored).length, 1);
    });

    test('valid tabs come back without an error and keep their history', () {
      final restored = service.restore([
        BrowserTab(
          id: 't1',
          type: BrowserTabType.web,
          title: 'Example',
          location: 'https://example.com/page',
          history: [
            const TabHistoryEntry(
                location: 'https://example.com/page', title: 'Example', type: BrowserTabType.web),
          ],
        ),
      ]);
      expect(restored.single.error, isNull);
      expect(restored.single.history.length, 1);
      expect(restored.single.loading, isFalse);
    });

    test('an unusable address is reported instead of dropped', () {
      final restored = service.restore([
        const BrowserTab(
            id: 't1', type: BrowserTabType.web, title: 'Old', location: 'javascript:alert(1)'),
      ]);
      expect(restored.single.error, TabRestoreService.invalidAddressMessage);
    });

    test('a missing file is reported for readers and the player', () {
      final restored = service.restore([
        const BrowserTab(
            id: 'r', type: BrowserTabType.epub, title: 'Book', location: '/books/gone.epub'),
        const BrowserTab(
            id: 'v', type: BrowserTabType.player, title: 'Film', location: '/video/gone.mkv'),
        const BrowserTab(
            id: 'ok', type: BrowserTabType.pdf, title: 'Paper', location: '/docs/kept.pdf'),
      ]);
      expect(restored[0].error, TabRestoreService.missingFileMessage);
      expect(restored[1].error, TabRestoreService.missingFileMessage);
      expect(restored[2].error, isNull);
    });

    test('a local HTML bundle is validated through its file path', () {
      final restored = service.restore([
        const BrowserTab(
            id: 'w',
            type: BrowserTabType.web,
            title: 'Offline',
            location: 'file:///content/kept/index.html'),
        const BrowserTab(
            id: 'x',
            type: BrowserTabType.web,
            title: 'Offline',
            location: 'file:///content/gone/index.html'),
      ]);
      expect(restored[0].error, isNull);
      expect(restored[1].error, TabRestoreService.missingFileMessage);
    });

    test('a torrent tab survives restoration even if it points at nothing yet', () {
      final restored = service.restore([
        const BrowserTab(
            id: 'h',
            type: BrowserTabType.torrent,
            title: 'Torrent',
            location: '0123456789abcdef0123456789abcdef01234567'),
      ]);
      expect(restored.single.error, isNull);
    });

    test('the ceiling trims least-recently-visited tabs and keeps workspace order', () {
      final stored = [
        for (var i = 0; i < TabRestoreService.maxRestoredTabs + 5; i++)
          BrowserTab(
            id: 't$i',
            type: BrowserTabType.web,
            title: 'p$i',
            location: 'https://h$i.example/',
            lastVisitedAtMs: 1000 + i,
          ),
      ];
      final restored = service.restore(stored);
      expect(restored.length, TabRestoreService.maxRestoredTabs);
      expect(restored.first.id, 't5', reason: 'the five oldest were trimmed');
      expect(restored.map((t) => t.id).toList(),
          [for (var i = 5; i < TabRestoreService.maxRestoredTabs + 5; i++) 't$i']);
    });

    test('the stored active tab stays active, exactly one of them', () {
      final restored = service.restore([
        const BrowserTab(
            id: 'a', type: BrowserTabType.web, title: 'A', location: 'https://a.example/'),
        const BrowserTab(
            id: 'b',
            type: BrowserTabType.web,
            title: 'B',
            location: 'https://b.example/',
            active: true),
      ]);
      final set = service.toTabSet(restored);
      expect(set.activeId, 'b');
      expect(set.tabs.where((t) => t.active).length, 1);
    });
  });

  group('BrowserTab persistence', () {
    test('a row round-trips with its history and active flag', () {
      final tab = BrowserTab(
        id: 't1',
        type: BrowserTabType.web,
        title: 'Example',
        location: 'https://example.com/2',
        history: const [
          TabHistoryEntry(location: 'https://example.com/1', title: 'One', type: BrowserTabType.web),
          TabHistoryEntry(location: 'https://example.com/2', title: 'Two', type: BrowserTabType.web),
        ],
        historyIndex: 1,
        active: true,
        scrollOffset: 42,
        lastVisitedAtMs: 99,
      );
      final back = BrowserTab.fromMap(tab.toMap(sortOrder: 0));
      expect(back.id, 't1');
      expect(back.location, 'https://example.com/2');
      expect(back.history.length, 2);
      expect(back.historyIndex, 1);
      expect(back.active, isTrue);
      expect(back.scrollOffset, 42);
      expect(back.canGoBack, isTrue);
    });

    test('a corrupt history blob degrades to an empty history, not a crash', () {
      final back = BrowserTab.fromMap({
        'id': 't1',
        'type': 'web',
        'title': 'X',
        'location': 'https://example.com/',
        'history_json': '{not json',
        'history_index': 3,
      });
      expect(back.history, isEmpty);
      expect(back.canGoBack, isFalse);
    });

    test('an unknown tab type falls back to home instead of throwing', () {
      expect(BrowserTabType.parse('something-new'), BrowserTabType.home);
      expect(BrowserTabType.parse(null), BrowserTabType.home);
    });
  });
}

bool _onlyExisting(String path) =>
    path == '/docs/kept.pdf' || path == '/content/kept/index.html';
