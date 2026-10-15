import '../../core/result.dart';
import '../manifests/source_manifest.dart';
import '../sync/sync_models.dart';

/// A publisher's cloud configuration, validated from its manifest.
class PublisherConfig {
  final String providerType;
  final Uri endpoint;
  final int protocolVersion;
  final int schemaVersion;
  final Set<String> capabilities;
  final String authMethod;
  final List<String> scopes;
  final String? publisherIdentity;

  const PublisherConfig({
    required this.providerType,
    required this.endpoint,
    required this.protocolVersion,
    required this.schemaVersion,
    required this.capabilities,
    required this.authMethod,
    required this.scopes,
    this.publisherIdentity,
  });

  /// The highest protocol version this build understands.
  static const int supportedProtocolVersion = 1;

  static Result<PublisherConfig> fromManifest(CloudProviderConfig c) {
    final uri = Uri.tryParse(c.endpoint);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return const Err('cloud endpoint must be an absolute https URL');
    }
    if (c.protocolVersion > supportedProtocolVersion) {
      return Err('cloud protocol v${c.protocolVersion} is newer than supported '
          'v$supportedProtocolVersion');
    }
    return Ok(PublisherConfig(
      providerType: c.providerType,
      endpoint: uri,
      protocolVersion: c.protocolVersion,
      schemaVersion: c.schemaVersion,
      capabilities: c.capabilities.toSet(),
      authMethod: c.authMethod,
      scopes: c.scopes,
      publisherIdentity: c.publisherIdentity,
    ));
  }
}

/// Authentication for a provider. Implementations keep credentials in secure
/// storage; nothing here ever writes a token to the database or logs.
abstract class CloudAuthAdapter {
  String get method;
  bool get isAuthenticated;
  Future<Result<void>> signIn();
  Future<void> signOut();
}

/// A publisher-operated cloud backend implementing the documented protocol.
abstract class CloudProvider {
  String get id;
  PublisherConfig get config;
  CloudAuthAdapter get auth;

  /// Declared capabilities (must be reported honestly; the sync engine checks).
  Set<String> get capabilities;
  int get protocolVersion;

  Future<Result<List<SyncRecord>>> pull(String collection, {DateTime? since});
  Future<Result<SyncRecord>> push(SyncRecord record);
  Future<Result<void>> delete(String collection, String key);
}

abstract class CloudProviderFactory {
  String get providerType;
  Result<CloudProvider> create(PublisherConfig config, CloudAuthAdapter auth);
}

/// Maps a provider type from a manifest to a concrete adapter.
class CloudProviderRegistry {
  final Map<String, CloudProviderFactory> _factories;
  CloudProviderRegistry(List<CloudProviderFactory> factories)
      : _factories = {for (final f in factories) f.providerType: f};

  Result<CloudProvider> create(PublisherConfig config, CloudAuthAdapter auth) {
    final f = _factories[config.providerType];
    if (f == null) return Err('unsupported cloud provider type "${config.providerType}"');
    return f.create(config, auth);
  }

  bool supports(String providerType) => _factories.containsKey(providerType);
}
