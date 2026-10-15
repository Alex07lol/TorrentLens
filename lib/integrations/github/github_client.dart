import 'dart:convert';
import '../../core/result.dart';
import '../media_resolver/http_fetcher.dart';
import 'github_models.dart';

enum GitHubError { notFound, rateLimited, unauthorized, network, malformedResponse, httpStatus }

/// Read-only GitHub API client. No authentication is required for public
/// repositories; a token is only used to raise the anonymous rate limit and is
/// never persisted unless the user opts in (it lives in secure storage).
class GitHubClient {
  final HttpFetcher fetcher;
  final String? token;
  final String? etagCacheKeyPrefix;

  const GitHubClient(this.fetcher, {this.token, this.etagCacheKeyPrefix});

  Map<String, String> _headers() => {
        'accept': 'application/vnd.github+json',
        'x-github-api-version': '2022-11-28',
        if (token != null && token!.isNotEmpty) 'authorization': 'Bearer $token',
      };

  Future<Result<List<GitHubRelease>>> listReleases(String owner, String repo,
      {int perPage = 30}) async {
    final uri = Uri.https('api.github.com', '/repos/$owner/$repo/releases',
        {'per_page': '$perPage'});
    final res = await _get(uri);
    if (res.isErr) return Err(res.errorOrNull()!);
    final body = res.valueOrNull!;
    final decoded = _decodeList(body);
    if (decoded == null) return const Err(GitHubError.malformedResponse);
    final releases = <GitHubRelease>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final tag = item['tag_name'];
      if (tag is! String) continue;
      releases.add(GitHubRelease(
        tagName: tag,
        name: item['name'] as String?,
        body: item['body'] as String?,
        publishedAt: DateTime.tryParse('${item['published_at']}'),
        prerelease: item['prerelease'] == true,
        draft: item['draft'] == true,
        assets: _assets(item['assets']),
      ));
    }
    return Ok(releases);
  }

  Future<Result<GitHubRelease>> latestRelease(String owner, String repo) async {
    final uri = Uri.https('api.github.com', '/repos/$owner/$repo/releases/latest');
    final res = await _get(uri);
    if (res.isErr) return Err(res.errorOrNull()!);
    final item = _decodeMap(res.valueOrNull!);
    if (item == null || item['tag_name'] is! String) {
      return const Err(GitHubError.malformedResponse);
    }
    return Ok(GitHubRelease(
      tagName: item['tag_name'] as String,
      name: item['name'] as String?,
      body: item['body'] as String?,
      publishedAt: DateTime.tryParse('${item['published_at']}'),
      prerelease: item['prerelease'] == true,
      draft: item['draft'] == true,
      assets: _assets(item['assets']),
    ));
  }

  /// Fetches a raw text resource (e.g. a release asset) with the same limits.
  Future<Result<String>> fetchText(String url, {int maxBytes = 1024 * 1024}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return const Err(GitHubError.malformedResponse);
    }
    try {
      final r = await fetcher.get(uri, maxBytes: maxBytes, headers: _headers());
      if (r.statusCode == 404) return const Err(GitHubError.notFound);
      if (r.statusCode >= 400) return const Err(GitHubError.httpStatus);
      return Ok(r.body);
    } catch (_) {
      return const Err(GitHubError.network);
    }
  }

  Future<Result<String>> _get(Uri uri) async {
    HttpFetchResponse r;
    try {
      r = await fetcher.get(uri, maxBytes: 2 * 1024 * 1024, headers: _headers());
    } catch (_) {
      return const Err(GitHubError.network);
    }
    if (r.statusCode == 404) return const Err(GitHubError.notFound);
    if (r.statusCode == 401) return const Err(GitHubError.unauthorized);
    if (r.statusCode == 403 || r.statusCode == 429) {
      final remaining = r.headers['x-ratelimit-remaining'];
      if (remaining == '0' || r.statusCode == 429) return const Err(GitHubError.rateLimited);
      return const Err(GitHubError.unauthorized);
    }
    if (r.statusCode >= 400) return const Err(GitHubError.httpStatus);
    return Ok(r.body);
  }

  List<GitHubAsset> _assets(Object? raw) {
    if (raw is! List) return const [];
    final out = <GitHubAsset>[];
    for (final a in raw) {
      if (a is! Map) continue;
      final name = a['name'];
      final url = a['browser_download_url'];
      if (name is! String || url is! String) continue;
      out.add(GitHubAsset(
        name: name,
        browserDownloadUrl: url,
        sizeBytes: a['size'] is int ? a['size'] as int : 0,
        contentType: a['content_type'] as String?,
      ));
    }
    return out;
  }

  Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  List? _decodeList(String body) {
    final d = _decode(body);
    return d is List ? d : null;
  }

  Map<String, Object?>? _decodeMap(String body) {
    final d = _decode(body);
    return d is Map ? d.cast<String, Object?>() : null;
  }
}
