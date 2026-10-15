import '../../core/result.dart';
import '../github/semantic_version.dart';
import '../security/url_policy.dart';
import 'source_manifest.dart';

enum ManifestError {
  notAnObject,
  wrongType,
  missingField,
  unsupportedSchemaVersion,
  invalidPublisherId,
  invalidSourceId,
  invalidVersion,
  invalidTimestamp,
  invalidUrl,
  insecureEndpoint,
  missingContentLocation,
  invalidFileMetadata,
  invalidCloudConfig,
  unsupportedCapability,
  signatureWithoutKey,
  tooManyFiles,
}

/// Performs strict, fail-closed parsing and cross-field validation of a
/// publisher manifest. Nothing here executes publisher-supplied data: unknown
/// capabilities are rejected rather than ignored, and a manifest can never
/// request a new permission or an executable payload.
class ManifestValidator {
  static const int maxFiles = 20000;

  /// Capabilities the app actually implements. A manifest that declares
  /// anything else is rejected so it cannot silently opt into future behaviour.
  static const Set<String> supportedCapabilities = {
    'torrent',
    'library',
    'reader',
    'player',
    'bookmarks',
    'reading_progress',
    'playback_position',
    'subscriptions',
    'cloud_sync',
    'notes',
  };

  static const Set<String> supportedProviderTypes = {'supabase', 'firebase', 'rest'};
  static const Set<String> supportedAuthMethods = {
    'none',
    'supabase_anon',
    'firebase',
    'bearer_oauth',
  };

  static Result<SourceManifest> parse(Object? decoded) {
    if (decoded is! Map) return const Err(ManifestError.notAnObject);

    T? req<T>(String key) {
      final v = decoded[key];
      if (v is! T) return null;
      return v;
    }

    final schemaVersion = decoded['schemaVersion'];
    if (schemaVersion is! int) {
      return decoded.containsKey('schemaVersion')
          ? const Err(ManifestError.wrongType)
          : const Err(ManifestError.missingField);
    }
    if (schemaVersion != SourceManifest.supportedSchemaVersion) {
      return const Err(ManifestError.unsupportedSchemaVersion);
    }

    final publisherId = req<String>('publisherId');
    if (publisherId == null || !_validId(publisherId)) {
      return const Err(ManifestError.invalidPublisherId);
    }
    final sourceId = req<String>('sourceId');
    if (sourceId == null || !_validId(sourceId)) {
      return const Err(ManifestError.invalidSourceId);
    }
    final name = req<String>('name');
    if (name == null || name.trim().isEmpty) {
      return const Err(ManifestError.missingField);
    }
    final contentVersion = req<String>('contentVersion');
    if (contentVersion == null || SemanticVersion.tryParse(contentVersion) == null) {
      return const Err(ManifestError.invalidVersion);
    }
    final publishedAtRaw = req<String>('publishedAt');
    final publishedAt =
        publishedAtRaw == null ? null : DateTime.tryParse(publishedAtRaw);
    if (publishedAt == null) return const Err(ManifestError.invalidTimestamp);

    final releaseUrl = req<String>('releaseUrl');
    if (releaseUrl == null) return const Err(ManifestError.missingField);
    if (UrlPolicy.evaluate(releaseUrl, use: UrlUse.fetch).isErr) {
      return const Err(ManifestError.invalidUrl);
    }

    final magnetUri = decoded['magnetUri'];
    final torrentUrl = decoded['torrentUrl'];
    if (magnetUri == null && torrentUrl == null) {
      return const Err(ManifestError.missingContentLocation);
    }
    if (magnetUri != null && magnetUri is! String) {
      return const Err(ManifestError.wrongType);
    }
    if (torrentUrl != null) {
      if (torrentUrl is! String) return const Err(ManifestError.wrongType);
      if (UrlPolicy.evaluate(torrentUrl, use: UrlUse.fetch).isErr) {
        return const Err(ManifestError.invalidUrl);
      }
    }

    // Files
    final rawFiles = decoded['files'];
    final files = <ManifestFile>[];
    if (rawFiles != null) {
      if (rawFiles is! List) return const Err(ManifestError.wrongType);
      if (rawFiles.length > maxFiles) return const Err(ManifestError.tooManyFiles);
      for (final f in rawFiles) {
        if (f is! Map) return const Err(ManifestError.invalidFileMetadata);
        final path = f['path'];
        final size = f['sizeBytes'];
        if (path is! String || path.trim().isEmpty) {
          return const Err(ManifestError.invalidFileMetadata);
        }
        if (path.startsWith('/') || path.split('/').contains('..')) {
          return const Err(ManifestError.invalidFileMetadata);
        }
        if (size is! int || size < 0) {
          return const Err(ManifestError.invalidFileMetadata);
        }
        final sha = f['sha256'];
        if (sha != null && (sha is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha))) {
          return const Err(ManifestError.invalidFileMetadata);
        }
        files.add(ManifestFile(path: path, sizeBytes: size, sha256: sha as String?));
      }
    }

    // Capabilities
    final rawCaps = decoded['capabilities'];
    final capabilities = <String>[];
    if (rawCaps != null) {
      if (rawCaps is! List) return const Err(ManifestError.wrongType);
      for (final c in rawCaps) {
        if (c is! String) return const Err(ManifestError.wrongType);
        if (!supportedCapabilities.contains(c)) {
          return const Err(ManifestError.unsupportedCapability);
        }
        capabilities.add(c);
      }
    }

    // Signature
    final signature = decoded['signature'];
    final signingKeyId = decoded['signingKeyId'];
    if (signature != null && signature is! String) {
      return const Err(ManifestError.wrongType);
    }
    if (signature is String && signature.isNotEmpty) {
      if (signingKeyId is! String || signingKeyId.trim().isEmpty) {
        return const Err(ManifestError.signatureWithoutKey);
      }
    }

    // Cloud provider config
    CloudProviderConfig? cloud;
    final rawCloud = decoded['cloud'];
    if (rawCloud != null) {
      if (rawCloud is! Map) return const Err(ManifestError.invalidCloudConfig);
      final parsed = _parseCloud(rawCloud);
      if (parsed == null) return const Err(ManifestError.invalidCloudConfig);
      cloud = parsed;
    }

    // Compatibility
    CompatibilityRequirement? compatibility;
    final rawCompat = decoded['compatibility'];
    if (rawCompat != null) {
      if (rawCompat is! Map) return const Err(ManifestError.wrongType);
      final minVer = rawCompat['minAppVersion'];
      final platforms = rawCompat['platforms'];
      if (minVer != null && minVer is! String) return const Err(ManifestError.wrongType);
      if (platforms != null && platforms is! List) return const Err(ManifestError.wrongType);
      compatibility = CompatibilityRequirement(
        minAppVersion: minVer as String?,
        platforms: (platforms as List?)?.map((e) => '$e').toList() ?? const ['android'],
      );
      if (!compatibility.platforms.contains('android')) {
        // A manifest that does not list Android is not usable here.
        return const Err(ManifestError.unsupportedCapability);
      }
    }

    // Update policy
    var checkIntervalHours = 24;
    var autoDownload = false;
    final rawPolicy = decoded['updatePolicy'];
    if (rawPolicy != null) {
      if (rawPolicy is! Map) return const Err(ManifestError.wrongType);
      final ci = rawPolicy['checkIntervalHours'];
      if (ci != null) {
        if (ci is! int || ci < 1 || ci > 24 * 30) return const Err(ManifestError.wrongType);
        checkIntervalHours = ci;
      }
      final ad = rawPolicy['autoDownload'];
      if (ad != null) {
        if (ad is! bool) return const Err(ManifestError.wrongType);
        autoDownload = ad;
      }
    }

    final changelog = decoded['changelog'];
    final description = decoded['description'];
    if (changelog != null && changelog is! String) return const Err(ManifestError.wrongType);
    if (description != null && description is! String) return const Err(ManifestError.wrongType);

    return Ok(SourceManifest(
      schemaVersion: schemaVersion,
      publisherId: publisherId,
      sourceId: sourceId,
      name: name,
      description: description as String?,
      contentVersion: contentVersion,
      publishedAt: publishedAt,
      releaseUrl: releaseUrl,
      magnetUri: magnetUri as String?,
      torrentUrl: torrentUrl as String?,
      files: List.unmodifiable(files),
      signature: signature as String?,
      signingKeyId: signingKeyId as String?,
      cloud: cloud,
      capabilities: List.unmodifiable(capabilities),
      compatibility: compatibility,
      changelog: changelog as String?,
      updatePolicy: UpdatePolicy(
          checkIntervalHours: checkIntervalHours, autoDownload: autoDownload),
    ));
  }

  static CloudProviderConfig? _parseCloud(Map raw) {
    final type = raw['providerType'];
    final endpoint = raw['endpoint'];
    final protocolVersion = raw['protocolVersion'];
    final schemaVersion = raw['schemaVersion'];
    if (type is! String || !supportedProviderTypes.contains(type)) return null;
    if (endpoint is! String) return null;
    if (protocolVersion is! int || protocolVersion < 1) return null;
    if (schemaVersion is! int || schemaVersion < 1) return null;

    // Cloud endpoints carry user data; plain HTTP is never acceptable.
    final uri = Uri.tryParse(endpoint);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    if (UrlPolicy.isPrivateHost(uri.host)) return null;

    final authMethod = raw['authMethod'];
    if (authMethod is! String || !supportedAuthMethods.contains(authMethod)) return null;

    final caps = raw['capabilities'];
    final scopes = raw['scopes'];
    final capabilities = caps is List ? caps.map((e) => '$e').toList() : <String>[];
    final scopeList = scopes is List ? scopes.map((e) => '$e').toList() : <String>[];
    for (final c in capabilities) {
      if (!supportedCapabilities.contains(c)) return null;
    }

    return CloudProviderConfig(
      providerType: type,
      endpoint: endpoint,
      protocolVersion: protocolVersion,
      schemaVersion: schemaVersion,
      capabilities: capabilities,
      authMethod: authMethod,
      scopes: scopeList,
      publisherIdentity: raw['publisherIdentity'] as String?,
      verificationUrl: raw['verificationUrl'] as String?,
    );
  }

  static bool _validId(String s) =>
      s.length >= 2 && s.length <= 128 && RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(s);
}
