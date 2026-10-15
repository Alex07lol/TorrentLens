import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/domain/github/update_evaluator.dart';
import 'package:torrentlens/domain/manifests/manifest_validator.dart';
import 'package:torrentlens/domain/security/signatures.dart';
import 'package:torrentlens/domain/security/trusted_keys.dart';
import 'package:torrentlens/integrations/github/github_client.dart';
import 'package:torrentlens/integrations/github/manifest_discovery.dart';
import 'package:torrentlens/integrations/github/update_checker.dart';
import 'package:torrentlens/integrations/media_resolver/http_fetcher.dart';

class FakeFetcher extends HttpFetcher {
  final Map<String, HttpFetchResponse> routes;
  FakeFetcher(this.routes);
  @override
  Future<HttpFetchResponse> get(Uri url,
      {bool followRedirects = true,
      int maxBytes = 512 * 1024,
      Map<String, String>? headers,
      Duration timeout = const Duration(seconds: 20)}) async {
    final r = routes[url.toString()];
    if (r == null) throw StateError('no route for $url');
    return r;
  }
}

HttpFetchResponse j(String url, int status, String body,
        {Map<String, String> headers = const {}}) =>
    HttpFetchResponse(
        finalUrl: Uri.parse(url),
        statusCode: status,
        headers: {'content-type': 'application/json', ...headers},
        body: body);

String releaseJson(String tag,
        {List<Map<String, Object?>> assets = const [],
        bool prerelease = false,
        bool draft = false}) =>
    jsonEncode({
      'tag_name': tag,
      'name': tag,
      'body': 'notes',
      'published_at': '2026-0${tag.contains('2') ? '2' : '1'}-01T00:00:00Z',
      'prerelease': prerelease,
      'draft': draft,
      'assets': assets,
    });

Map<String, Object?> asset(String name, String url) =>
    {'name': name, 'browser_download_url': url, 'size': 100, 'content_type': 'application/json'};

Map<String, Object?> manifestJson({String version = '1.1.0', String? signature, String? keyId}) => {
      'schemaVersion': 1,
      'publisherId': 'pub.example',
      'sourceId': 'comic-x',
      'name': 'Example Comic',
      'contentVersion': version,
      'publishedAt': '2026-02-01T00:00:00Z',
      'releaseUrl': 'https://github.com/owner/repo/releases/tag/v$version',
      'magnetUri': 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
      'files': [],
      'capabilities': ['torrent', 'reader'],
      'updatePolicy': {'checkIntervalHours': 24, 'autoDownload': false},
      'signature': signature,
      'signingKeyId': keyId,
    };

void main() {
  group('GitHubClient', () {
    test('parses a release list including assets', () async {
      final f = FakeFetcher({
        'https://api.github.com/repos/owner/repo/releases?per_page=30': j(
            'https://api.github.com/repos/owner/repo/releases?per_page=30',
            200,
            jsonEncode([
              jsonDecode(releaseJson('v1.1.0', assets: [asset('comic.manifest.json', 'https://objects.githubusercontent.com/m')]))
            ])),
      });
      final client = GitHubClient(f);
      final r = await client.listReleases('owner', 'repo');
      expect(r.isOk, isTrue);
      final rel = r.valueOrNull!.single;
      expect(rel.tagName, 'v1.1.0');
      expect(rel.assets.single.name, 'comic.manifest.json');
      expect(rel.manifestAssetUrl, 'https://objects.githubusercontent.com/m');
    });

    test('reports rate limiting distinctly', () async {
      final f = FakeFetcher({
        'https://api.github.com/repos/owner/repo/releases?per_page=30': j(
            'https://api.github.com/repos/owner/repo/releases?per_page=30',
            403,
            '{"message":"API rate limit exceeded"}',
            headers: {'x-ratelimit-remaining': '0'}),
      });
      final r = await GitHubClient(f).listReleases('owner', 'repo');
      expect(r.errorOrNull(), GitHubError.rateLimited);
    });

    test('reports a missing repository as notFound', () async {
      final f = FakeFetcher({
        'https://api.github.com/repos/owner/repo/releases?per_page=30':
            j('https://api.github.com/repos/owner/repo/releases?per_page=30', 404, '{}'),
      });
      expect((await GitHubClient(f).listReleases('owner', 'repo')).errorOrNull(),
          GitHubError.notFound);
    });
  });

  group('ManifestDiscovery', () {
    test('prefers the most specific manifest asset name', () async {
      final f = FakeFetcher({
        'https://api.github.com/repos/owner/repo/releases?per_page=30': j(
            'https://api.github.com/repos/owner/repo/releases?per_page=30',
            200,
            jsonEncode([
              jsonDecode(releaseJson('v1.1.0', assets: [
                asset('app.apk', 'https://x/apk'),
                asset('manifest.json', 'https://x/generic'),
                asset('comic.manifest.json', 'https://x/specific'),
              ]))
            ])),
      });
      final releases = (await GitHubClient(f).listReleases('owner', 'repo')).valueOrNull!;
      expect(ManifestDiscovery.findManifestAsset(releases.single)!.name, 'comic.manifest.json');
    });

    test('skips prereleases and drafts when choosing the newest', () async {
      final f = FakeFetcher({
        'https://api.github.com/repos/owner/repo/releases?per_page=30': j(
            'https://api.github.com/repos/owner/repo/releases?per_page=30',
            200,
            jsonEncode([
              jsonDecode(releaseJson('v2.0.0', prerelease: true, assets: [asset('a.manifest.json', 'https://x/pre')])),
              jsonDecode(releaseJson('v1.5.0', assets: [asset('a.manifest.json', 'https://x/stable')])),
            ])),
      });
      final releases = (await GitHubClient(f).listReleases('owner', 'repo')).valueOrNull!;
      expect(ManifestDiscovery.newestWithManifest(releases)!.tagName, 'v1.5.0');
    });
  });

  group('UpdateChecker end-to-end', () {
    late SimpleKeyPair kp;
    late List<int> pub;
    late TrustedKeyRegistry registry;

    setUp(() async {
      final algo = Ed25519();
      kp = await algo.newKeyPair();
      pub = (await kp.extractPublicKey()).bytes;
      registry = InMemoryTrustedKeyRegistry(
          [TrustedKey(keyId: 'k1', publisherId: 'pub.example', publicKey: pub)]);
    });

    Future<String> signedManifest() async {
      final algo = Ed25519();
      final base = manifestJson();
      final parsed = ManifestValidator.parse(base).valueOrNull!;
      final sig = await algo.sign(
          PublisherSignatureVerifier.canonicalize(parsed.signablePayload()), keyPair: kp);
      return jsonEncode({...base, 'signature': base64Encode(sig.bytes), 'signingKeyId': 'k1'});
    }

    test('detects a verified update', () async {
      final body = await signedManifest();
      final f = FakeFetcher({
        'https://api.github.com/repos/owner/repo/releases?per_page=30': j(
            'https://api.github.com/repos/owner/repo/releases?per_page=30',
            200,
            jsonEncode([jsonDecode(releaseJson('v1.1.0', assets: [asset('c.manifest.json', 'https://x/m')]))])),
        'https://x/m': j('https://x/m', 200, body),
      });
      final out = await UpdateChecker(GitHubClient(f), registry)
          .check(owner: 'owner', repo: 'repo', installedVersion: '1.0.0');
      expect(out.status, UpdateStatus.updateAvailable);
      expect(out.trust, TrustStatus.verified);
      expect(out.releaseTag, 'v1.1.0');
    });

    test('a tampered manifest verifies as invalid and is not offered as trusted', () async {
      final body = await signedManifest();
      final tampered = jsonDecode(body) as Map<String, Object?>;
      tampered['contentVersion'] = '9.9.9'; // changed after signing
      final f = FakeFetcher({
        'https://api.github.com/repos/owner/repo/releases?per_page=30': j(
            'https://api.github.com/repos/owner/repo/releases?per_page=30',
            200,
            jsonEncode([jsonDecode(releaseJson('v1.1.0', assets: [asset('c.manifest.json', 'https://x/m')]))])),
        'https://x/m': j('https://x/m', 200, jsonEncode(tampered)),
      });
      final out = await UpdateChecker(GitHubClient(f), registry)
          .check(owner: 'owner', repo: 'repo', installedVersion: '1.0.0');
      expect(out.trust, TrustStatus.invalidSignature);
      expect(out.status, UpdateStatus.updateAvailableUntrusted);
    });

    test('an unknown publisher never verifies', () async {
      final body = await signedManifest();
      final f = FakeFetcher({
        'https://api.github.com/repos/owner/repo/releases?per_page=30': j(
            'https://api.github.com/repos/owner/repo/releases?per_page=30',
            200,
            jsonEncode([jsonDecode(releaseJson('v1.1.0', assets: [asset('c.manifest.json', 'https://x/m')]))])),
        'https://x/m': j('https://x/m', 200, body),
      });
      final out = await UpdateChecker(GitHubClient(f), InMemoryTrustedKeyRegistry(const []))
          .check(owner: 'owner', repo: 'repo', installedVersion: '1.0.0');
      expect(out.trust, TrustStatus.unknownPublisher);
      expect(out.status, UpdateStatus.updateAvailableUntrusted);
    });

    test('a release without a manifest does not fabricate an update', () async {
      final f = FakeFetcher({
        'https://api.github.com/repos/owner/repo/releases?per_page=30': j(
            'https://api.github.com/repos/owner/repo/releases?per_page=30',
            200,
            jsonEncode([jsonDecode(releaseJson('v1.1.0', assets: [asset('app.apk', 'https://x/apk')]))])),
      });
      final out = await UpdateChecker(GitHubClient(f), registry)
          .check(owner: 'owner', repo: 'repo', installedVersion: '1.0.0');
      expect(out.status, UpdateStatus.upToDate);
      expect(out.error, UpdateCheckError.noManifest);
    });
  });
}
