import '../../core/result.dart';
import '../../domain/cloud/cloud_contracts.dart';
import '../../domain/sync/sync_models.dart';
import 'anonymous_auth_adapter.dart';

/// A fully in-memory provider used by tests and by the "try a provider" flow.
/// It implements the same contract as a real backend, including conflict
/// metadata, so the sync engine can be exercised without a network.
class MockCloudProvider implements CloudProvider {
  final Map<String, Map<String, SyncRecord>> _store = {};
  final CloudAuthAdapter _auth;
  final PublisherConfig _config;

  MockCloudProvider(this._config, [CloudAuthAdapter? auth])
      : _auth = auth ?? AnonymousAuthAdapter();

  @override
  String get id => 'mock';
  @override
  PublisherConfig get config => _config;
  @override
  CloudAuthAdapter get auth => _auth;
  @override
  Set<String> get capabilities => _config.capabilities;
  @override
  int get protocolVersion => _config.protocolVersion;

  @override
  Future<Result<List<SyncRecord>>> pull(String collection, {DateTime? since}) async {
    final items = _store[collection]?.values.toList() ?? <SyncRecord>[];
    final filtered = since == null
        ? items
        : items.where((r) => r.updatedAt.isAfter(since)).toList();
    return Ok(filtered);
  }

  @override
  Future<Result<SyncRecord>> push(SyncRecord record) async {
    final col = _store.putIfAbsent(record.type, () => {});
    final existing = col[record.key];
    if (existing != null && existing.version > record.version) {
      // Stale write: reject rather than silently clobber a newer remote record.
      return Err('stale write for ${record.key} (remote v${existing.version})');
    }
    col[record.key] = record;
    return Ok(record);
  }

  @override
  Future<Result<void>> delete(String collection, String key) async {
    _store[collection]?.remove(key);
    return const Ok(null);
  }

  /// Test/inspection helper.
  Map<String, Map<String, SyncRecord>> get store => _store;
}

class MockCloudProviderFactory implements CloudProviderFactory {
  @override
  String get providerType => 'mock';
  @override
  Result<CloudProvider> create(PublisherConfig config, CloudAuthAdapter auth) =>
      Ok(MockCloudProvider(config, auth));
}
