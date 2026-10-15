import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/domain/github/update_evaluator.dart';
import 'package:torrentlens/domain/manifests/source_manifest.dart';
import 'package:torrentlens/domain/security/signatures.dart';

SourceManifest manifest(String version, {bool autoDownload = false}) => SourceManifest(
      schemaVersion: 1,
      publisherId: 'pub',
      sourceId: 'src',
      name: 'n',
      description: null,
      contentVersion: version,
      publishedAt: DateTime.utc(2026, 1, 1),
      releaseUrl: 'https://example.com/r',
      magnetUri: 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
      torrentUrl: null,
      files: const [],
      signature: null,
      signingKeyId: null,
      cloud: null,
      capabilities: const [],
      compatibility: null,
      changelog: null,
      updatePolicy: UpdatePolicy(autoDownload: autoDownload),
    );

void main() {
  test('reports up to date for equal versions', () {
    final d = UpdateEvaluator.evaluate(
        manifest: manifest('1.2.0'), trust: TrustStatus.verified, installedVersion: '1.2.0');
    expect(d.status, UpdateStatus.upToDate);
    expect(d.hasUpdate, isFalse);
  });

  test('reports an update, and marks it trusted when the publisher verifies', () {
    final d = UpdateEvaluator.evaluate(
        manifest: manifest('1.3.0'), trust: TrustStatus.verified, installedVersion: '1.2.0');
    expect(d.status, UpdateStatus.updateAvailable);
    expect(d.hasUpdate, isTrue);
  });

  test('flags a newer version from an unverified publisher', () {
    final d = UpdateEvaluator.evaluate(
        manifest: manifest('1.3.0'), trust: TrustStatus.unknownPublisher, installedVersion: '1.2.0');
    expect(d.status, UpdateStatus.updateAvailableUntrusted);
    expect(d.installableWithoutPrompt, isFalse);
  });

  test('only allows unattended installs for verified publishers that opted in', () {
    final d = UpdateEvaluator.evaluate(
        manifest: manifest('2.0.0', autoDownload: true),
        trust: TrustStatus.verified,
        installedVersion: '1.0.0');
    expect(d.installableWithoutPrompt, isTrue);

    final untrusted = UpdateEvaluator.evaluate(
        manifest: manifest('2.0.0', autoDownload: true),
        trust: TrustStatus.invalidSignature,
        installedVersion: '1.0.0');
    expect(untrusted.installableWithoutPrompt, isFalse);
  });

  test('detects a downgrade', () {
    final d = UpdateEvaluator.evaluate(
        manifest: manifest('1.0.0'), trust: TrustStatus.verified, installedVersion: '1.2.0');
    expect(d.status, UpdateStatus.downgrade);
  });
}
