import 'dart:convert';
import '../../core/result.dart';
import '../../domain/cloud/cloud_contracts.dart';
import '../../domain/security/url_policy.dart';
import '../../domain/sync/sync_models.dart';
import '../media_resolver/http_fetcher.dart';

/// A self-hosted REST adapter implementing the documented publisher protocol:
///
///   `GET  {endpoint}/{collection}?since=...`        -> `[SyncRecord, ...]`
///   `POST {endpoint}/{collection}`                 -> `SyncRecord`
///   `DELETE {endpoint}/{collection}/{key}`         -> `204`
///
/// Every response is validated against the schema before use, so a
/// misbehaving backend cannot inject arbitrary records.
class RestCloudProvider implements CloudProvider {
  final HttpFetcher fetcher;
  final PublisherConfig _config;
  final CloudAuthAdapter _auth;
  final Map<String, String> extraHeaders;

  RestCloudProvider(this.fetcher, this._config, this._auth, {this.extraHeaders = const {}});

  @override
  String get id => _config.providerType;
  @override
  PublisherConfig get config => _config;
  @override
  CloudAuthAdapter get auth => _auth;
  @override
  Set<String> get capabilities => _config.capabilities;
  @override
  int get protocolVersion => _config.protocolVersion;

  Map<String, String> _headers() => {...extraHeaders};

  Uri _collectionUri(String collection, {DateTime? since}) {
    final base = _config.endpoint.toString().replaceAll(RegExp(r'/+$'), '');
    final u = Uri.parse('$base/${Uri.encodeComponent(collection)}');
    return since == null
        ? u
        : u.replace(queryParameters: {'since': since.toUtc().toIso8601String()});
  }

  @override
  Future<Result<List<SyncRecord>>> pull(String collection, {DateTime? since}) async {
    final uri = _collectionUri(collection, since: since);
    final guard = UrlPolicy.evaluate(uri.toString(), use: UrlUse.fetch);
    if (guard.isErr) return Err('cloud endpoint rejected: ${guard.errorOrNull()}');
    try {
      final r = await fetcher.get(uri, headers: _headers());
      if (r.statusCode == 401 || r.statusCode == 403) {
        return const Err('cloud request not authorised');
      }
      if (r.statusCode >= 400) return Err('cloud HTTP ${r.statusCode}');
      final decoded = jsonDecode(r.body);
      if (decoded is! List) return const Err('cloud response is not a list');
      final out = <SyncRecord>[];
      for (final item in decoded) {
        if (item is! Map) return const Err('cloud record is not an object');
        final rec = SyncRecord.fromJson(item.cast<String, Object?>());
        if (rec == null) return const Err('cloud record failed schema validation');
        out.add(rec);
      }
      return Ok(out);
    } catch (e) {
      return Err('cloud pull failed: $e');
    }
  }

  @override
  Future<Result<SyncRecord>> push(SyncRecord record) async {
    final uri = _collectionUri(record.type);
    final guard = UrlPolicy.evaluate(uri.toString(), use: UrlUse.fetch);
    if (guard.isErr) return Err('cloud endpoint rejected: ${guard.errorOrNull()}');
    try {
      final r = await fetcher.post(uri, body: record.toJson(), headers: _headers());
      if (r.statusCode == 401 || r.statusCode == 403) {
        return const Err('cloud write not authorised');
      }
      if (r.statusCode == 409) return const Err('cloud conflict (409): remote is newer');
      if (r.statusCode >= 400) return Err('cloud HTTP ${r.statusCode}');
      final decoded = jsonDecode(r.body);
      if (decoded is! Map) return const Err('cloud push response is not an object');
      final rec = SyncRecord.fromJson(decoded.cast<String, Object?>());
      if (rec == null) return const Err('cloud push response failed validation');
      return Ok(rec);
    } catch (e) {
      return Err('cloud push failed: $e');
    }
  }

  @override
  Future<Result<void>> delete(String collection, String key) async {
    final uri = Uri.parse('${_collectionUri(collection)}/${Uri.encodeComponent(key)}');
    final guard = UrlPolicy.evaluate(uri.toString(), use: UrlUse.fetch);
    if (guard.isErr) return Err('cloud endpoint rejected: ${guard.errorOrNull()}');
    try {
      final r = await fetcher.post(uri, headers: {..._headers(), 'x-http-method-override': 'DELETE'});
      if (r.statusCode >= 400) return Err('cloud HTTP ${r.statusCode}');
      return const Ok(null);
    } catch (e) {
      return Err('cloud delete failed: $e');
    }
  }
}

class RestCloudProviderFactory implements CloudProviderFactory {
  final HttpFetcher fetcher;
  RestCloudProviderFactory(this.fetcher);
  @override
  String get providerType => 'rest';
  @override
  Result<CloudProvider> create(PublisherConfig config, CloudAuthAdapter auth) =>
      Ok(RestCloudProvider(fetcher, config, auth));
}
