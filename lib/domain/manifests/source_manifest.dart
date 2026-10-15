/// Versioned publisher manifest model (schema v1).
///
/// Mirrors `docs/source-manifest.md`. Parsing is strict: unknown *major*
/// schema versions are rejected, unknown minor additions are ignored, and
/// manifests may never carry executable content — only data that the app
/// validates before it is used.
class SourceManifest {
  /// The schema version this build understands. A manifest with a higher major
  /// version is rejected rather than partially interpreted.
  static const int supportedSchemaVersion = 1;

  final int schemaVersion;
  final String publisherId;
  final String sourceId;
  final String name;
  final String? description;
  final String contentVersion;
  final DateTime publishedAt;
  final String releaseUrl;
  final String? magnetUri;
  final String? torrentUrl;
  final List<ManifestFile> files;
  final String? signature;
  final String? signingKeyId;
  final CloudProviderConfig? cloud;
  final List<String> capabilities;
  final CompatibilityRequirement? compatibility;
  final String? changelog;
  final UpdatePolicy updatePolicy;

  const SourceManifest({
    required this.schemaVersion,
    required this.publisherId,
    required this.sourceId,
    required this.name,
    required this.description,
    required this.contentVersion,
    required this.publishedAt,
    required this.releaseUrl,
    required this.magnetUri,
    required this.torrentUrl,
    required this.files,
    required this.signature,
    required this.signingKeyId,
    required this.cloud,
    required this.capabilities,
    required this.compatibility,
    required this.changelog,
    required this.updatePolicy,
  });

  /// The exact map that is signed. Everything except `signature`/`signingKeyId`
  /// is included, so altering any field invalidates the signature.
  Map<String, Object?> signablePayload() {
    final m = toJson();
    m.remove('signature');
    m.remove('signingKeyId');
    return m;
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'publisherId': publisherId,
        'sourceId': sourceId,
        'name': name,
        if (description != null) 'description': description,
        'contentVersion': contentVersion,
        'publishedAt': publishedAt.toUtc().toIso8601String(),
        'releaseUrl': releaseUrl,
        if (magnetUri != null) 'magnetUri': magnetUri,
        if (torrentUrl != null) 'torrentUrl': torrentUrl,
        'files': files.map((f) => f.toJson()).toList(),
        if (signature != null) 'signature': signature,
        if (signingKeyId != null) 'signingKeyId': signingKeyId,
        if (cloud != null) 'cloud': cloud!.toJson(),
        'capabilities': capabilities,
        if (compatibility != null) 'compatibility': compatibility!.toJson(),
        if (changelog != null) 'changelog': changelog,
        'updatePolicy': updatePolicy.toJson(),
      };
}

class ManifestFile {
  final String path;
  final int sizeBytes;
  final String? sha256;
  const ManifestFile({required this.path, required this.sizeBytes, this.sha256});

  Map<String, Object?> toJson() => {
        'path': path,
        'sizeBytes': sizeBytes,
        if (sha256 != null) 'sha256': sha256,
      };
}

class CloudProviderConfig {
  final String providerType; // supabase | firebase | rest
  final String endpoint;
  final int protocolVersion;
  final int schemaVersion;
  final List<String> capabilities;
  final String authMethod; // none | supabase_anon | firebase | bearer_oauth
  final List<String> scopes;
  final String? publisherIdentity;
  final String? verificationUrl;

  const CloudProviderConfig({
    required this.providerType,
    required this.endpoint,
    required this.protocolVersion,
    required this.schemaVersion,
    required this.capabilities,
    required this.authMethod,
    required this.scopes,
    this.publisherIdentity,
    this.verificationUrl,
  });

  Map<String, Object?> toJson() => {
        'providerType': providerType,
        'endpoint': endpoint,
        'protocolVersion': protocolVersion,
        'schemaVersion': schemaVersion,
        'capabilities': capabilities,
        'authMethod': authMethod,
        'scopes': scopes,
        if (publisherIdentity != null) 'publisherIdentity': publisherIdentity,
        if (verificationUrl != null) 'verificationUrl': verificationUrl,
      };
}

class CompatibilityRequirement {
  final String? minAppVersion;
  final List<String> platforms;
  const CompatibilityRequirement({this.minAppVersion, this.platforms = const ['android']});

  Map<String, Object?> toJson() => {
        if (minAppVersion != null) 'minAppVersion': minAppVersion,
        'platforms': platforms,
      };
}

class UpdatePolicy {
  final int checkIntervalHours;
  final bool autoDownload;
  const UpdatePolicy({this.checkIntervalHours = 24, this.autoDownload = false});

  Map<String, Object?> toJson() =>
      {'checkIntervalHours': checkIntervalHours, 'autoDownload': autoDownload};
}
