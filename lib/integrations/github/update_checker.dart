import 'dart:convert';
import '../../core/result.dart';
import '../../domain/github/update_evaluator.dart';
import '../../domain/manifests/manifest_validator.dart';
import '../../domain/manifests/source_manifest.dart';
import '../../domain/security/signatures.dart';
import '../../domain/security/trusted_keys.dart';
import 'github_client.dart';
import 'manifest_discovery.dart';

enum UpdateCheckError { noReleases, noManifest, rateLimited, network, invalidManifest, fetchFailed }

class UpdateCheckOutcome {
  final UpdateStatus status;
  final SourceManifest? manifest;
  final TrustStatus trust;
  final SignatureCheckResult? signature;
  final UpdateCheckError? error;
  final String? releaseTag;
  final String? manifestUrl;
  final String? message;

  const UpdateCheckOutcome({
    required this.status,
    this.manifest,
    this.trust = TrustStatus.unsigned,
    this.signature,
    this.error,
    this.releaseTag,
    this.manifestUrl,
    this.message,
  });
}

/// Ties the GitHub client, the manifest validator and the signature verifier
/// together: fetch releases → discover a manifest asset → validate it strictly
/// → verify the publisher signature → decide whether an update exists.
///
/// The signature is verified over the manifest with its signature block removed,
/// so a tampered field is reported as [TrustStatus.invalidSignature] and the
/// update is offered only as untrusted.
class UpdateChecker {
  final GitHubClient client;
  final TrustedKeyRegistry keys;
  const UpdateChecker(this.client, this.keys);

  Future<UpdateCheckOutcome> check({
    required String owner,
    required String repo,
    String? installedVersion,
    bool includePrereleases = false,
  }) async {
    final releases = await client.listReleases(owner, repo);
    if (releases.isErr) {
      final e = releases.errorOrNull();
      return UpdateCheckOutcome(
        status: UpdateStatus.invalidVersions,
        error: switch (e) {
          GitHubError.rateLimited => UpdateCheckError.rateLimited,
          GitHubError.network => UpdateCheckError.network,
          _ => UpdateCheckError.network,
        },
        message: 'GitHub API error: $e',
      );
    }
    final list = releases.valueOrNull!;
    if (list.isEmpty) {
      return const UpdateCheckOutcome(
          status: UpdateStatus.invalidVersions, error: UpdateCheckError.noReleases);
    }

    final pool = includePrereleases ? list : list.where((r) => !r.prerelease).toList();
    final release = ManifestDiscovery.newestWithManifest(pool);
    if (release == null) {
      return UpdateCheckOutcome(
        status: UpdateStatus.upToDate,
        error: UpdateCheckError.noManifest,
        message: 'No release in $owner/$repo publishes a supported manifest.',
      );
    }
    final asset = ManifestDiscovery.findManifestAsset(release)!;

    final raw = await client.fetchText(asset.browserDownloadUrl);
    if (raw.isErr) {
      return UpdateCheckOutcome(
        status: UpdateStatus.invalidVersions,
        error: UpdateCheckError.fetchFailed,
        releaseTag: release.tagName,
        manifestUrl: asset.browserDownloadUrl,
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(raw.valueOrNull!);
    } catch (_) {
      return UpdateCheckOutcome(
        status: UpdateStatus.invalidVersions,
        error: UpdateCheckError.invalidManifest,
        releaseTag: release.tagName,
        message: 'Manifest is not valid JSON.',
      );
    }

    final parsed = ManifestValidator.parse(decoded);
    if (parsed.isErr) {
      return UpdateCheckOutcome(
        status: UpdateStatus.invalidVersions,
        error: UpdateCheckError.invalidManifest,
        releaseTag: release.tagName,
        message: 'Manifest rejected: ${parsed.errorOrNull()}',
      );
    }
    final manifest = parsed.valueOrNull!;

    final sig = await PublisherSignatureVerifier.verify(
      messageBytes: PublisherSignatureVerifier.canonicalize(manifest.signablePayload()),
      signatureBase64: manifest.signature,
      keyId: manifest.signingKeyId,
      registry: keys,
    );

    final decision = UpdateEvaluator.evaluate(
      manifest: manifest,
      trust: sig.status,
      installedVersion: installedVersion,
    );

    return UpdateCheckOutcome(
      status: decision.status,
      manifest: manifest,
      trust: sig.status,
      signature: sig,
      releaseTag: release.tagName,
      manifestUrl: asset.browserDownloadUrl,
      message: decision.summary,
    );
  }

  /// Release history for the rollback-friendly version list.
  Future<Result<List<SourceManifest>>> releaseHistory(
      String owner, String repo) async {
    final releases = await client.listReleases(owner, repo, perPage: 50);
    if (releases.isErr) return Err(releases.errorOrNull()!);
    final manifests = <SourceManifest>[];
    for (final rel in releases.valueOrNull!) {
      final asset = ManifestDiscovery.findManifestAsset(rel);
      if (asset == null) continue;
      final raw = await client.fetchText(asset.browserDownloadUrl);
      if (raw.isErr) continue;
      try {
        final parsed = ManifestValidator.parse(jsonDecode(raw.valueOrNull!));
        if (parsed.isOk) manifests.add(parsed.valueOrNull!);
      } catch (_) {
        // skip malformed history entries
      }
    }
    return Ok(manifests);
  }
}
