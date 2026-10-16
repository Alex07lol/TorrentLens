import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:torrentlens/app/services.dart';
import 'package:torrentlens/data/db/app_database.dart';
import 'package:torrentlens/data/repositories/sqflite_repositories.dart';
import 'package:torrentlens/data/secure/secure_store.dart';
import 'package:torrentlens/domain/models/subscription.dart';
import 'package:torrentlens/domain/security/signatures.dart';
import 'package:torrentlens/domain/security/trusted_keys.dart';
import 'package:torrentlens/features/subscriptions/subscription_update_service.dart';
import 'package:torrentlens/features/subscriptions/update_worker.dart';
import 'package:torrentlens/integrations/cloud_providers/cloud_registry.dart';
import 'package:torrentlens/integrations/github/github_client.dart';
import 'package:torrentlens/integrations/github/update_checker.dart';
import 'package:torrentlens/integrations/media_resolver/http_fetcher.dart';
import 'package:torrentlens/integrations/media_resolver/media_link_resolver.dart';

import '../support/fake_torrent_engine.dart';

class FakeFetcher extends HttpFetcher {
  final Map<String, HttpFetchResponse> routes;
  final List<Uri> requested = [];
  FakeFetcher(this.routes);

  @override
  Future<HttpFetchResponse> get(Uri url,
      {bool followRedirects = true,
      int maxBytes = 512 * 1024,
      Map<String, String>? headers,
      Duration timeout = const Duration(seconds: 20)}) async {
    requested.add(url);
    final r = routes[url.toString()];
    if (r == null) throw StateError('no route for $url');
    return r;
  }
}

HttpFetchResponse json(String url, int status, Object body,
        {Map<String, String> headers = const {}}) =>
    HttpFetchResponse(
      finalUrl: Uri.parse(url),
      statusCode: status,
      headers: {'content-type': 'application/json', ...headers},
      body: body is String ? body : jsonEncode(body),
    );

Map<String, Object?> release(String tag, {String? manifestAssetUrl}) => {
      'tag_name': tag,
      'name': tag,
      'body': 'notes',
      'published_at': '2026-02-01T00:00:00Z',
      'prerelease': false,
      'draft': false,
      'assets': [
        if (manifestAssetUrl != null)
          {
            'name': 'comic.manifest.json',
            'browser_download_url': manifestAssetUrl,
            'size': 100,
            'content_type': 'application/json',
          },
      ],
    };

Map<String, Object?> manifest({String version = '2.0.0'}) => {
      'schemaVersion': 1,
      'publisherId': 'pub.example',
      'sourceId': 'comic-x',
      'name': 'Example Comic',
      'contentVersion': version,
      'publishedAt': '2026-02-01T00:00:00Z',
      'releaseUrl': 'https://github.com/owner/repo/releases/tag/v$version',
      'magnetUri': 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
      'files': <Object?>[],
      'capabilities': ['torrent', 'reader'],
      'updatePolicy': {'checkIntervalHours': 24, 'autoDownload': false},
      'signature': null,
      'signingKeyId': null,
    };

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase db;
  late AppServices services;

  Future<AppServices> buildServices(FakeFetcher fetcher) async {
    db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final trusted = InMemoryTrustedKeyRegistry(const []);
    final github = GitHubClient(fetcher);
    return AppServices(
      db: db,
      torrents: SqfliteTorrentTaskRepository(db.db),
      subscriptions: SqfliteSubscriptionRepository(db.db),
      library: SqfliteLibraryRepository(db.db),
      progress: SqfliteProgressRepository(db.db),
      settings: SqfliteSettingsRepository(db.db),
      syncQueue: SqfliteSyncQueueRepository(db.db),
      tabs: SqfliteTabRepository(db.db),
      engine: FakeTorrentEngine(fileLengthBytes: 1, relativePath: 'x'),
      fetcher: fetcher,
      github: github,
      updateChecker: UpdateChecker(github, trusted),
      cloudRegistry: CloudProviderRegistries.standard(
        fetcher: fetcher,
        includeMock: false,
        supabaseAnonKey: (_) => null,
        supabaseAccessToken: () => null,
      ),
      trustedKeys: trusted,
      secure: InMemorySecureStore(),
      resolver: MediaLinkResolver(fetcher),
      deviceId: 'test-device',
      defaultDownloadDir: '/tmp/torrentlens-test',
    );
  }

  tearDown(() async => db.close());

  Subscription subscribed(
    String id,
    String repo, {
    int? lastCheckedAtMs,
    int intervalHours = 24,
  }) =>
      Subscription(
        id: id,
        publisherId: 'owner',
        owner: 'owner',
        repo: repo,
        title: repo,
        lastCheckedAtMs: lastCheckedAtMs,
        checkIntervalHours: intervalHours,
      );

  test('a due subscription is checked, recorded and reported exactly once', () async {
    final f = FakeFetcher({
      'https://api.github.com/repos/owner/repo/releases?per_page=30':
          json('https://api.github.com/repos/owner/repo/releases?per_page=30', 200,
              [release('v2.0.0', manifestAssetUrl: 'https://objects.example/m.json')]),
      'https://objects.example/m.json': json('https://objects.example/m.json', 200, manifest()),
    });
    services = await buildServices(f);
    await services.subscriptions.upsert(subscribed('s1', 'repo'));

    final notified = <List<SubscriptionCheckResult>>[];
    final results = await runUpdateCheck(
      services: services,
      notify: (r) async => notified.add(r),
    );

    expect(results.length, 1);
    expect(results.single.hasUpdate, isTrue);
    // Unsigned is reported as unsigned — never silently "verified".
    expect(results.single.outcome.trust, TrustStatus.unsigned);
    expect(results.single.subscription.trustStatus, 'unsigned');
    expect(results.single.subscription.latestVersion, '2.0.0');
    expect(results.single.subscription.lastCheckedAtMs, isNotNull);
    expect(results.single.subscription.magnetUri, contains('magnet:'));

    expect(notified.length, 1, reason: 'one pass, one notification');
    expect(notified.single.single.subscription.id, 's1');

    // The check timestamp is persisted, so the interval is respected.
    final stored = await services.subscriptions.byRepo('owner', 'repo');
    expect(stored!.latestVersion, '2.0.0');

    notified.clear();
    final second = await runUpdateCheck(services: services, notify: (r) async => notified.add(r));
    expect(second, isEmpty, reason: 'not due again for another 24 hours');
    expect(notified, isEmpty);
    expect(f.requested.length, 2, reason: 'no extra GitHub calls');
  });

  test('a subscription that is not due is not contacted at all', () async {
    services = await buildServices(FakeFetcher({}));
    await services.subscriptions.upsert(subscribed('s1', 'repo',
        lastCheckedAtMs: DateTime.now().millisecondsSinceEpoch));
    final results = await runUpdateCheck(services: services);
    expect(results, isEmpty);
  });

  test('a repository with no manifest publishes nothing and notifies nobody', () async {
    final f = FakeFetcher({
      'https://api.github.com/repos/owner/repo/releases?per_page=30':
          json('https://api.github.com/repos/owner/repo/releases?per_page=30', 200, [release('v1.0.0')]),
    });
    services = await buildServices(f);
    await services.subscriptions.upsert(subscribed('s1', 'repo'));

    final notified = <List<SubscriptionCheckResult>>[];
    final results = await runUpdateCheck(services: services, notify: (r) async => notified.add(r));
    expect(results.single.hasUpdate, isFalse);
    expect(results.single.message, contains('No manifest asset'));
    expect(notified, isEmpty);
  });

  test('a GitHub rate limit is recorded, described and does not loop', () async {
    final f = FakeFetcher({
      'https://api.github.com/repos/owner/repo/releases?per_page=30': json(
        'https://api.github.com/repos/owner/repo/releases?per_page=30',
        403,
        {'message': 'API rate limit exceeded'},
        headers: const {'x-ratelimit-remaining': '0'},
      ),
    });
    services = await buildServices(f);
    await services.subscriptions.upsert(subscribed('s1', 'repo'));

    final results = await runUpdateCheck(services: services);
    expect(results.single.hasUpdate, isFalse);
    expect(results.single.message, contains('rate limit'));
    final stored = await services.subscriptions.byRepo('owner', 'repo');
    expect(stored!.lastCheckedAtMs, isNotNull,
        reason: 'a failed check still counts as the attempt, so retries back off');
  });

  test('a broken subscription never blocks the rest of the queue', () async {
    final f = FakeFetcher({
      'https://api.github.com/repos/owner/good/releases?per_page=30':
          json('https://api.github.com/repos/owner/good/releases?per_page=30', 200,
              [release('v3.0.0', manifestAssetUrl: 'https://objects.example/m.json')]),
      'https://objects.example/m.json': json('https://objects.example/m.json', 200, manifest()),
    });
    services = await buildServices(f);
    await services.subscriptions.upsert(subscribed('bad', 'broken'));
    await services.subscriptions.upsert(subscribed('good', 'good'));

    // No notify callback here on purpose: the default one talks to the
    // notification plugin, which is not registered in a test isolate, and a
    // notification failure must never fail the check itself.
    final results = await runUpdateCheck(services: services);
    expect(results.length, 2);
    expect(results.map((r) => r.subscription.id), containsAll(['bad', 'good']));
    final good = results.firstWhere((r) => r.subscription.id == 'good');
    expect(good.hasUpdate, isTrue);
  });
}
