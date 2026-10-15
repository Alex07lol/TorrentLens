import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/domain/manifests/manifest_validator.dart';
import 'package:torrentlens/domain/manifests/source_manifest.dart';

Map<String, Object?> validManifest({
  Object? schemaVersion = 1,
  String publisherId = 'pub.example',
  String sourceId = 'comic-x',
  String contentVersion = '1.0.0',
  String publishedAt = '2026-01-01T00:00:00Z',
  String releaseUrl = 'https://example.com/releases/1.0.0',
  Object? magnetUri = 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
  Object? torrentUrl,
  Object? files,
  Object? cloud,
  Object? capabilities,
  Object? signature,
  Object? signingKeyId,
  Object? compatibility,
  Object? updatePolicy,
}) =>
    {
      'schemaVersion': schemaVersion,
      'publisherId': publisherId,
      'sourceId': sourceId,
      'name': 'Example Comic',
      'contentVersion': contentVersion,
      'publishedAt': publishedAt,
      'releaseUrl': releaseUrl,
      'magnetUri': magnetUri,
      'torrentUrl': torrentUrl,
      'files': files,
      'cloud': cloud,
      'capabilities': capabilities,
      'signature': signature,
      'signingKeyId': signingKeyId,
      'compatibility': compatibility,
      'updatePolicy': updatePolicy,
    };

void main() {
  test('parses a minimal valid manifest', () {
    final r = ManifestValidator.parse(validManifest());
    expect(r.isOk, isTrue, reason: '${r.errorOrNull()}');
    expect(r.valueOrNull!.publisherId, 'pub.example');
    expect(r.valueOrNull!.updatePolicy.checkIntervalHours, 24);
  });

  test('accepts a complete manifest with files, cloud config and signature', () {
    final r = ManifestValidator.parse(validManifest(
      files: [
        {'path': 'a/b.cbz', 'sizeBytes': 1000, 'sha256': 'a' * 64},
      ],
      capabilities: ['torrent', 'cloud_sync', 'reading_progress'],
      signature: 'AAAA',
      signingKeyId: 'key-2026',
      cloud: {
        'providerType': 'supabase',
        'endpoint': 'https://project.supabase.co',
        'protocolVersion': 1,
        'schemaVersion': 1,
        'capabilities': ['cloud_sync', 'reading_progress'],
        'authMethod': 'supabase_anon',
        'scopes': ['reading_progress'],
      },
      updatePolicy: {'checkIntervalHours': 12, 'autoDownload': false},
    ));
    expect(r.isOk, isTrue, reason: '${r.errorOrNull()}');
    expect(r.valueOrNull!.files.single.path, 'a/b.cbz');
    expect(r.valueOrNull!.cloud!.providerType, 'supabase');
    expect(r.valueOrNull!.signingKeyId, 'key-2026');
  });

  test('rejects a future major schema version', () {
    expect(ManifestValidator.parse(validManifest(schemaVersion: 2)).errorOrNull(),
        ManifestError.unsupportedSchemaVersion);
  });

  test('rejects a manifest with no content location', () {
    expect(ManifestValidator.parse(validManifest(magnetUri: null)).errorOrNull(),
        ManifestError.missingContentLocation);
  });

  test('rejects a bad version and a bad timestamp', () {
    expect(ManifestValidator.parse(validManifest(contentVersion: 'latest')).errorOrNull(),
        ManifestError.invalidVersion);
    expect(ManifestValidator.parse(validManifest(publishedAt: 'yesterday')).errorOrNull(),
        ManifestError.invalidTimestamp);
  });

  test('rejects unknown capabilities rather than ignoring them', () {
    expect(ManifestValidator.parse(validManifest(capabilities: ['torrent', 'run_shell'])).errorOrNull(),
        ManifestError.unsupportedCapability);
  });

  test('rejects a signature with no signing-key id', () {
    expect(ManifestValidator.parse(validManifest(signature: 'AAAA')).errorOrNull(),
        ManifestError.signatureWithoutKey);
  });

  test('rejects file metadata with traversal paths or bad hashes', () {
    expect(
        ManifestValidator.parse(validManifest(files: [
          {'path': '../../evil', 'sizeBytes': 1},
        ])).errorOrNull(),
        ManifestError.invalidFileMetadata);
    expect(
        ManifestValidator.parse(validManifest(files: [
          {'path': 'ok.bin', 'sizeBytes': 1, 'sha256': 'zz'},
        ])).errorOrNull(),
        ManifestError.invalidFileMetadata);
  });

  test('rejects insecure or private cloud endpoints', () {
    Map<String, Object?> cloud(String endpoint) => {
          'providerType': 'rest',
          'endpoint': endpoint,
          'protocolVersion': 1,
          'schemaVersion': 1,
          'authMethod': 'none',
        };
    expect(ManifestValidator.parse(validManifest(cloud: cloud('http://api.example.com'))).errorOrNull(),
        ManifestError.invalidCloudConfig);
    expect(ManifestValidator.parse(validManifest(cloud: cloud('https://10.0.0.1/api'))).errorOrNull(),
        ManifestError.invalidCloudConfig);
    expect(
        ManifestValidator.parse(validManifest(cloud: cloud('https://api.example.com')))
            .isOk,
        isTrue);
  });

  test('rejects unsupported cloud provider types and auth methods', () {
    expect(
        ManifestValidator.parse(validManifest(cloud: {
          'providerType': 'dropbox',
          'endpoint': 'https://x.example.com',
          'protocolVersion': 1,
          'schemaVersion': 1,
          'authMethod': 'none',
        })).errorOrNull(),
        ManifestError.invalidCloudConfig);
  });

  test('signablePayload omits the signature fields so it can be verified', () {
    final r = ManifestValidator.parse(
        validManifest(signature: 'AAAA', signingKeyId: 'k1'));
    final payload = r.valueOrNull!.signablePayload();
    expect(payload.containsKey('signature'), isFalse);
    expect(payload.containsKey('signingKeyId'), isFalse);
    expect(payload['schemaVersion'], SourceManifest.supportedSchemaVersion);
  });
}
