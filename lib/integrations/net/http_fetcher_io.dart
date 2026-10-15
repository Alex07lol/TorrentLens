import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../media_resolver/http_fetcher.dart';

/// Production [HttpFetcher] backed by `package:http`.
///
/// The body is read incrementally and hard-capped at [maxBytes] so a hostile or
/// broken server cannot exhaust device memory. Redirects are *not* followed
/// here when the caller passes `followRedirects: false` (the resolver validates
/// each hop itself).
class HttpFetcherImpl implements HttpFetcher {
  final http.Client _client;
  final String userAgent;
  HttpFetcherImpl({http.Client? client, this.userAgent = 'TorrentLens/1.0 (+android)'})
      : _client = client ?? http.Client();

  @override
  Future<HttpFetchResponse> get(
    Uri url, {
    bool followRedirects = true,
    int maxBytes = 512 * 1024,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final req = http.Request('GET', url);
    req.followRedirects = followRedirects;
    req.maxRedirects = 5;
    req.headers['user-agent'] = userAgent;
    req.headers['accept'] = 'text/html,application/xhtml+xml,application/json,text/*;q=0.9,*/*;q=0.5';
    if (headers != null) req.headers.addAll(headers);

    final streamed = await _client.send(req).timeout(timeout);
    final bytes = <int>[];
    var truncated = false;
    await for (final chunk in streamed.stream) {
      bytes.addAll(chunk);
      if (bytes.length >= maxBytes) {
        truncated = true;
        break;
      }
    }
    final body = utf8.decode(bytes, allowMalformed: true);
    final lowered = <String, String>{};
    streamed.headers.forEach((k, v) => lowered[k.toLowerCase()] = v);
    return HttpFetchResponse(
      finalUrl: streamed.request?.url ?? url,
      statusCode: streamed.statusCode,
      headers: lowered,
      body: body,
      truncated: truncated,
    );
  }

  @override
  Future<HttpFetchResponse> post(
    Uri url, {
    Object? body,
    int maxBytes = 512 * 1024,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final req = http.Request('POST', url);
    req.headers['user-agent'] = userAgent;
    req.headers['content-type'] = 'application/json';
    if (headers != null) req.headers.addAll(headers);
    req.body = body is String ? body : jsonEncode(body);
    final streamed = await _client.send(req).timeout(timeout);
    final bytes = <int>[];
    var truncated = false;
    await for (final chunk in streamed.stream) {
      bytes.addAll(chunk);
      if (bytes.length >= maxBytes) {
        truncated = true;
        break;
      }
    }
    final lowered = <String, String>{};
    streamed.headers.forEach((k, v) => lowered[k.toLowerCase()] = v);
    return HttpFetchResponse(
      finalUrl: streamed.request?.url ?? url,
      statusCode: streamed.statusCode,
      headers: lowered,
      body: utf8.decode(bytes, allowMalformed: true),
      truncated: truncated,
    );
  }

  void close() => _client.close();
}
