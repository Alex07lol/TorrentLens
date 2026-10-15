import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/core/result.dart';
import 'package:torrentlens/domain/cloud/cloud_contracts.dart';
import 'package:torrentlens/domain/manifests/source_manifest.dart';
import 'package:torrentlens/domain/sync/conflict_resolver.dart';
import 'package:torrentlens/domain/sync/sync_models.dart';
import 'package:torrentlens/integrations/cloud_providers/anonymous_auth_adapter.dart';
import 'package:torrentlens/integrations/cloud_providers/cloud_registry.dart';
import 'package:torrentlens/integrations/cloud_providers/cloud_sync_engine.dart';
import 'package:torrentlens/integrations/cloud_providers/mock_cloud_provider.dart';
import 'package:torrentlens/integrations/cloud_providers/rest_cloud_provider.dart';
import 'package:torrentlens/integrations/cloud_providers/supabase_cloud_provider.dart';
import 'package:torrentlens/integrations/media_resolver/http_fetcher.dart';

PublisherConfig config({String providerType = 'rest', String endpoint = 'https://api.example.com'}) =>
    PublisherConfig(
      providerType: providerType,
      endpoint: Uri.parse(endpoint),
      protocolVersion: 1,
      schemaVersion: 1,
      capabilities: const {'cloud_sync', 'reading_progress', 'bookmarks'},
      authMethod: 'none',
      scopes: const [],
    );

SyncRecord rec(String key, int version, String when, String device, Map<String, Object?> payload,
        {String type = 'reading_progress'}) =>
    SyncRecord(
        key: key,
        type: type,
        payload: payload,
        version: version,
        updatedAt: DateTime.parse(when),
        deviceId: device);

class PostFetcher extends HttpFetcher {
  final Map<String, HttpFetchResponse> gets;
  final Map<String, HttpFetchResponse> posts;
  final List<Uri> posted = [];
  PostFetcher(this.gets, {this.posts = const {}});
  @override
  Future<HttpFetchResponse> get(Uri url,
      {bool followRedirects = true,
      int maxBytes = 512 * 1024,
      Map<String, String>? headers,
      Duration timeout = const Duration(seconds: 20)}) async {
    final r = gets[url.toString()];
    if (r == null) throw StateError('no GET route for $url');
    return r;
  }

  @override
  Future<HttpFetchResponse> post(Uri url,
      {Object? body,
      int maxBytes = 512 * 1024,
      Map<String, String>? headers,
      Duration timeout = const Duration(seconds: 20)}) async {
    posted.add(url);
    final r = posts[url.toString()];
    if (r == null) throw StateError('no POST route for $url');
    return r;
  }
}

HttpFetchResponse res(String url, int status, String body,
        {Map<String, String> headers = const {}}) =>
    HttpFetchResponse(
        finalUrl: Uri.parse(url), statusCode: status, headers: headers, body: body);

void main() {
  group('PublisherConfig', () {
    test('accepts an https endpoint and rejects http or a newer protocol', () {
      final ok = PublisherConfig.fromManifest(const CloudProviderConfig(
          providerType: 'rest',
          endpoint: 'https://api.example.com',
          protocolVersion: 1,
          schemaVersion: 1,
          capabilities: [],
          authMethod: 'none',
          scopes: []));
      expect(ok.isOk, isTrue);
      final bad = PublisherConfig.fromManifest(const CloudProviderConfig(
          providerType: 'rest',
          endpoint: 'http://api.example.com',
          protocolVersion: 1,
          schemaVersion: 1,
          capabilities: [],
          authMethod: 'none',
          scopes: []));
      expect(bad.isErr, isTrue);
      final newer = PublisherConfig.fromManifest(const CloudProviderConfig(
          providerType: 'rest',
          endpoint: 'https://api.example.com',
          protocolVersion: 99,
          schemaVersion: 1,
          capabilities: [],
          authMethod: 'none',
          scopes: []));
      expect(newer.isErr, isTrue);
    });
  });

  group('MockCloudProvider', () {
    test('push then pull round-trips and rejects stale writes', () async {
      final p = MockCloudProvider(config(providerType: 'mock'));
      final r = rec('k', 3, '2026-01-01T00:00:00Z', 'device-a', {'fraction': 0.5});
      expect((await p.push(r)).isOk, isTrue);
      final pulled = await p.pull('reading_progress');
      expect(pulled.valueOrNull!.single.key, 'k');
      // stale write (lower version) must be rejected
      final stale = rec('k', 1, '2025-01-01T00:00:00Z', 'device-b', {'fraction': 0.1});
      expect((await p.push(stale)).isErr, isTrue);
    });
  });

  group('SyncEngine', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('pushes local-only records and pulls remote-only records', () async {
      final provider = MockCloudProvider(config(providerType: 'mock'));
      await provider.push(rec('remote-only', 2, '2026-01-01T00:00:00Z', 'device-b', {'fraction': 0.9}));
      final engine = SyncEngine(provider, 'device-a');
      final local = {'local-only': rec('local-only', 1, '2026-01-01T00:00:00Z', 'device-a', {'fraction': 0.1})};
      final report = await engine.sync(local, ['reading_progress']);
      expect(report.pushed, 1);
      expect(report.pulled, 1);
      expect(report.localUpdates.containsKey('remote-only'), isTrue);
      expect(provider.store['reading_progress']!.containsKey('local-only'), isTrue);
    });

    test('is idempotent on a second run', () async {
      final provider = MockCloudProvider(config(providerType: 'mock'));
      final engine = SyncEngine(provider, 'device-a');
      final local = {'k': rec('k', 1, '2026-01-01T00:00:00Z', 'device-a', {'fraction': 0.1})};
      await engine.sync(local, ['reading_progress']);
      final second = await engine.sync(local, ['reading_progress']);
      expect(second.hadErrors, isFalse);
      expect(second.pulled, 0);
      expect(second.merged, 0);
    });

    test('takes the newer remote record and reports a local update', () async {
      final provider = MockCloudProvider(config(providerType: 'mock'));
      await provider.push(rec('k', 5, '2026-03-01T00:00:00Z', 'device-b', {'fraction': 0.9}));
      final engine = SyncEngine(provider, 'device-a');
      final local = {'k': rec('k', 2, '2026-01-01T00:00:00Z', 'device-a', {'fraction': 0.1})};
      final report = await engine.sync(local, ['reading_progress']);
      expect(report.pulled, 1);
      expect(report.localUpdates['k']!.version, 5);
    });

    test('merges progress with the max fraction and pushes the merge', () async {
      final provider = MockCloudProvider(config(providerType: 'mock'));
      await provider.push(rec('k', 3, '2026-02-01T00:00:00Z', 'device-a', {'fraction': 0.8}));
      final engine = SyncEngine(provider, 'device-a',
          mergeStrategies: {'reading_progress': SyncConflictResolver.mergeProgress});
      final local = {'k': rec('k', 3, '2026-02-01T00:00:00Z', 'device-b', {'fraction': 0.2})};
      final report = await engine.sync(local, ['reading_progress']);
      expect(report.merged, 1);
      expect(provider.store['reading_progress']!['k']!.payload['fraction'], 0.8);
    });

    test('records a provider failure without throwing or losing local state', () async {
      final provider = _FailingProvider();
      final engine = SyncEngine(provider, 'device-a');
      final report = await engine.sync(
          {'k': rec('k', 1, '2026-01-01T00:00:00Z', 'device-a', {})}, ['reading_progress']);
      expect(report.hadErrors, isTrue);
      expect(report.pushed, 0);
    });
  });

  group('RestCloudProvider', () {
    test('pulls and validates the schema', () async {
      final body = jsonEncode([
        rec('k', 4, '2026-01-01T00:00:00Z', 'device-b', {'fraction': 0.4}).toJson()
      ]);
      final f = PostFetcher({
        'https://api.example.com/reading_progress': res(
            'https://api.example.com/reading_progress', 200, body,
            headers: {'content-type': 'application/json'}),
      });
      final p = RestCloudProvider(f, config(), AnonymousAuthAdapter());
      final r = await p.pull('reading_progress');
      expect(r.isOk, isTrue);
      expect(r.valueOrNull!.single.version, 4);
    });

    test('rejects a malformed record instead of accepting it', () async {
      final f = PostFetcher({
        'https://api.example.com/reading_progress': res(
            'https://api.example.com/reading_progress', 200, jsonEncode([
          {'nope': true}
        ])),
      });
      final p = RestCloudProvider(f, config(), AnonymousAuthAdapter());
      expect((await p.pull('reading_progress')).isErr, isTrue);
    });

    test('surfaces a 409 conflict on push', () async {
      final f = PostFetcher({}, posts: {
        'https://api.example.com/reading_progress':
            res('https://api.example.com/reading_progress', 409, '{}'),
      });
      final p = RestCloudProvider(f, config(), AnonymousAuthAdapter());
      final r = await p.push(rec('k', 1, '2026-01-01T00:00:00Z', 'device-a', {}));
      expect(r.isErr, isTrue);
      expect('${r.errorOrNull()}', contains('conflict'));
    });
  });

  group('Supabase + registry', () {
    test('registry refuses an unsupported provider type', () {
      final reg = CloudProviderRegistries.standard(
          fetcher: PostFetcher({}), includeMock: true);
      expect(reg.supports('rest'), isTrue);
      expect(reg.supports('mock'), isTrue);
      expect(reg.create(config(providerType: 'dropbox'), AnonymousAuthAdapter()).isErr, isTrue);
    });

    test('supabase factory needs an anon key and never bakes one in', () {
      final f = PostFetcher({});
      final noKey = SupabaseCloudProviderFactory(f, (_) => null, () => null);
      expect(noKey.create(config(providerType: 'supabase'), AnonymousAuthAdapter()).isErr, isTrue);
      final withKey = SupabaseCloudProviderFactory(f, (_) => 'public-anon-key', () => null);
      expect(withKey.create(config(providerType: 'supabase'), AnonymousAuthAdapter()).isOk, isTrue);
    });
  });
}

class _FailingProvider implements CloudProvider {
  @override
  String get id => 'failing';
  @override
  PublisherConfig get config => PublisherConfig(
      providerType: 'rest',
      endpoint: Uri.parse('https://api.example.com'),
      protocolVersion: 1,
      schemaVersion: 1,
      capabilities: const {},
      authMethod: 'none',
      scopes: const []);
  @override
  CloudAuthAdapter get auth => AnonymousAuthAdapter();
  @override
  Set<String> get capabilities => const {};
  @override
  int get protocolVersion => 1;
  @override
  Future<Result<List<SyncRecord>>> pull(String collection, {DateTime? since}) async =>
      const Err('offline');
  @override
  Future<Result<SyncRecord>> push(SyncRecord record) async => const Err('offline');
  @override
  Future<Result<void>> delete(String collection, String key) async => const Err('offline');
}
