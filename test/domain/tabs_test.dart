import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/domain/tabs/browser_address.dart';
import 'package:torrentlens/domain/tabs/browser_tab.dart';
import 'package:torrentlens/domain/tabs/tab_set.dart';

BrowserTab web(String id, String url, {String? title}) => BrowserTab(
      id: id,
      type: BrowserTabType.web,
      title: title ?? Uri.parse(url).host,
      location: url,
      history: [TabHistoryEntry(location: url, title: title ?? url, type: BrowserTabType.web)],
    );

void main() {
  group('TabSet — opening and switching', () {
    test('opens tabs in order and activates the new one', () {
      var set = TabSet.empty.open(BrowserTab.home('t1'));
      set = set.open(web('t2', 'https://a.example/'));
      set = set.open(web('t3', 'https://b.example/'));
      expect(set.length, 3);
      expect(set.activeId, 't3');
      expect(set.tabs.map((t) => t.id), ['t1', 't2', 't3']);
      expect(set.tabs.where((t) => t.active).length, 1);
    });

    test('switching keeps exactly one active tab', () {
      var set = TabSet.empty.open(BrowserTab.home('t1'));
      set = set.open(web('t2', 'https://a.example/'));
      set = set.activateTab('t1');
      expect(set.activeId, 't1');
      expect(set.tabs.firstWhere((t) => t.id == 't2').active, isFalse);
      expect(set.active!.id, 't1');
    });

    test('opening the same URL twice focuses the existing tab (no duplicates)', () {
      var set = TabSet.empty.open(web('t1', 'https://a.example/'));
      set = set.activateTab('t1');
      set = set.open(web('t2', 'https://a.example/'));
      expect(set.length, 1);
      expect(set.activeId, 't1');
    });

    test('a reader opened for a file already open focuses that tab, whichever reader', () {
      var set = TabSet.empty.open(const BrowserTab(
        id: 'r1',
        type: BrowserTabType.epub,
        title: 'Book',
        location: '/books/a.epub',
      ));
      set = set.open(const BrowserTab(
        id: 'r2',
        type: BrowserTabType.text,
        title: 'Book',
        location: '/books/a.epub',
      ));
      expect(set.length, 1);
      expect(set.activeId, 'r1');
    });

    test('openInBackground never steals focus', () {
      var set = TabSet.empty.open(BrowserTab.home('t1'));
      set = set.openInBackground(web('t2', 'https://a.example/'));
      expect(set.length, 2);
      expect(set.activeId, 't1');
    });

    test('only one blank home tab is ever kept', () {
      var set = TabSet.empty.open(BrowserTab.home('t1'));
      set = set.open(BrowserTab.home('t2'));
      expect(set.length, 1);
      expect(set.activeId, 't1');
    });
  });

  group('TabSet — closing', () {
    test('closing the active tab moves to the neighbour on its left', () {
      var set = TabSet.empty.open(web('t1', 'https://a.example/'));
      set = set.open(web('t2', 'https://b.example/'));
      set = set.open(web('t3', 'https://c.example/'));
      set = set.close('t3');
      expect(set.activeId, 't2');
      expect(set.length, 2);
    });

    test('closing an inactive tab leaves the active tab alone', () {
      var set = TabSet.empty.open(web('t1', 'https://a.example/'));
      set = set.open(web('t2', 'https://b.example/'));
      set = set.close('t1');
      expect(set.activeId, 't2');
      expect(set.tabs.single.id, 't2');
    });

    test('closing the last tab leaves one fresh blank tab', () {
      final set = TabSet.empty.open(web('t1', 'https://a.example/')).close('t1');
      expect(set.length, 1);
      expect(set.active!.type, BrowserTabType.home);
    });

    test('closeAll leaves a single blank tab and closing an unknown id changes nothing', () {
      var set = TabSet.empty.open(web('t1', 'https://a.example/'));
      set = set.open(web('t2', 'https://b.example/'));
      expect(set.close('nope').length, 2);
      final cleared = set.closeAll();
      expect(cleared.length, 1);
      expect(cleared.active!.type, BrowserTabType.home);
    });

    test('closeOthers keeps exactly the named tab', () {
      var set = TabSet.empty.open(web('t1', 'https://a.example/'));
      set = set.open(web('t2', 'https://b.example/'));
      set = set.open(web('t3', 'https://c.example/'));
      set = set.closeOthers('t2');
      expect(set.tabs.single.id, 't2');
      expect(set.activeId, 't2');
    });
  });

  group('TabSet — history', () {
    test('navigate pushes entries and back/forward move through them', () {
      var set = TabSet.empty.open(BrowserTab.home('t1'));
      set = set.navigate('t1',
          location: 'https://a.example/1',
          title: 'one',
          type: BrowserTabType.web);
      set = set.navigate('t1',
          location: 'https://a.example/2',
          title: 'two',
          type: BrowserTabType.web);
      expect(set.byId('t1')!.history.length, 2);
      expect(set.byId('t1')!.canGoBack, isTrue);
      expect(set.byId('t1')!.canGoForward, isFalse);

      set = set.back('t1');
      expect(set.byId('t1')!.location, 'https://a.example/1');
      expect(set.byId('t1')!.canGoForward, isTrue);

      set = set.forward('t1');
      expect(set.byId('t1')!.location, 'https://a.example/2');
    });

    test('navigating after going back truncates the forward entries', () {
      var set = TabSet.empty.open(web('t1', 'https://a.example/1'));
      set = set.navigate('t1', location: 'https://a.example/2', title: '2', type: BrowserTabType.web);
      set = set.back('t1');
      set = set.navigate('t1', location: 'https://a.example/3', title: '3', type: BrowserTabType.web);
      final tab = set.byId('t1')!;
      expect(tab.history.map((h) => h.location),
          ['https://a.example/1', 'https://a.example/3']);
      expect(tab.canGoForward, isFalse);
      expect(tab.location, 'https://a.example/3');
    });

    test('a replacing navigation does not grow history', () {
      var set = TabSet.empty.open(web('t1', 'https://a.example/1'));
      set = set.navigate('t1',
          location: 'https://a.example/1',
          title: 'one',
          type: BrowserTabType.web,
          push: false);
      expect(set.byId('t1')!.history.length, 1);
    });

    test('back and forward at the ends are no-ops', () {
      var set = TabSet.empty.open(web('t1', 'https://a.example/1'));
      final before = set.byId('t1')!;
      set = set.back('t1');
      expect(set.byId('t1')!.location, before.location);
      set = set.forward('t1');
      expect(set.byId('t1')!.location, before.location);
    });
  });

  group('TabSet — per-tab state isolation', () {
    test('one tab loading or failing never touches another tab', () {
      var set = TabSet.empty.open(web('t1', 'https://a.example/'));
      set = set.open(web('t2', 'https://b.example/'));
      set = set.setLoading('t2', true);
      expect(set.byId('t1')!.loading, isFalse);
      expect(set.byId('t2')!.loading, isTrue);

      set = set.setError('t1', 'boom');
      expect(set.byId('t1')!.error, 'boom');
      expect(set.byId('t2')!.error, isNull);
      expect(set.byId('t1')!.loading, isFalse, reason: 'an error ends the spinner');

      set = set.setError('t1', null);
      expect(set.byId('t1')!.error, isNull);
    });

    test('updating an unknown tab id is a no-op', () {
      final set = TabSet.empty.open(web('t1', 'https://a.example/'));
      expect(set.updateTab('nope', (t) => t.copyWith(title: 'x')).tabs.length, 1);
      expect(set.byId('t1')!.title, 'a.example');
    });

    test('titles and scroll offsets are remembered per tab', () {
      var set = TabSet.empty.open(web('t1', 'https://a.example/'));
      set = set.open(web('t2', 'https://b.example/'));
      set = set.setTitle('t2', 'B page');
      set = set.setScroll('t2', 1234);
      expect(set.byId('t1')!.title, 'a.example');
      expect(set.byId('t2')!.title, 'B page');
      expect(set.byId('t2')!.scrollOffset, 1234);
      expect(set.byId('t1')!.scrollOffset, 0);
    });
  });

  group('TabSet — resource budget', () {
    test('lowest-priority live tabs are evicted, the active tab never is', () {
      var set = TabSet.empty.open(BrowserTab.home('home'));
      for (var i = 0; i < 8; i++) {
        set = set.open(web('w$i', 'https://h$i.example/'));
      }
      set = set.activateTab('home');
      final live = set.liveIds(limit: 3);
      expect(live.length, 3);
      expect(live.first, 'home', reason: 'the active tab is always live');
      // The most recently visited web tabs are the ones kept.
      expect(live.contains('w7'), isTrue);
      expect(live.contains('w0'), isFalse);
    });

    test('byRecency is ordered most-recent-first', () {
      var set = TabSet.empty.open(web('t1', 'https://a.example/'));
      set = set.open(web('t2', 'https://b.example/'));
      set = set.activateTab('t1').touch('t1');
      expect(set.byRecency.first.id, 't1');
    });
  });

  group('BrowserAddress', () {
    test('accepts http and https URLs unchanged', () {
      expect(BrowserAddress.parse('https://example.com/a/b').url.toString(),
          'https://example.com/a/b');
      expect(BrowserAddress.parse('http://example.com/').url.toString(), 'http://example.com/');
    });

    test('adds https to a bare host', () {
      expect(BrowserAddress.parse('example.com/docs').url.toString(),
          'https://example.com/docs');
    });

    test('searches when the input is not an address', () {
      final parsed = BrowserAddress.parse('how to read cbz files');
      expect(parsed.isSearch, isTrue);
      expect(parsed.url!.host, 'duckduckgo.com');
      expect(parsed.url!.query, contains('cbz'));
    });

    test('recognizes magnets so the torrent flow can take over', () {
      final parsed = BrowserAddress.parse(
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567');
      expect(parsed.isMagnet, isTrue);
      expect(parsed.url, isNull);
    });

    test('refuses dangerous schemes, credentials and private addresses', () {
      expect(BrowserAddress.parse('javascript:alert(1)').ok, isFalse);
      expect(BrowserAddress.parse('file:///etc/passwd').ok, isFalse);
      final withCredentials = BrowserAddress.parse('https://user:pw@example.com/');
      expect(withCredentials.ok, isFalse);
      expect(withCredentials.rejection, contains('usernames or passwords'));
      expect(BrowserAddress.parse('http://127.0.0.1:8080/admin').rejection, contains('private'));
      expect(BrowserAddress.parse('   ').ok, isFalse);
    });

    test('the search template is configurable and the query is encoded', () {
      final parsed = BrowserAddress.parse('x y',
          searchTemplate: 'https://search.example/?q=%s');
      expect(parsed.url!.host, 'search.example');
      expect(parsed.url!.queryParameters['q'], 'x y');
    });

    test('display strips credentials', () {
      expect(BrowserAddress.display(Uri.parse('https://u:p@example.com/a')), 'https://example.com/a');
    });
  });
}
