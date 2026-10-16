import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
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

  /// Reads at most [maxBytes] from the response stream and reports whether the
  /// body was cut short. Reading incrementally means an unbounded or malicious
  /// `Content-Length` never allocates on the device.
  static Future<(Uint8List, bool)> _read(http.StreamedResponse response, int maxBytes) async {
    final bytes = BytesBuilder(copy: false);
    var truncated = false;
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maxBytes) {
        final take = maxBytes - bytes.length;
        if (take > 0) bytes.add(chunk.sublist(0, take));
        truncated = true;
        break;
      }
      bytes.add(chunk);
    }
    return (bytes.takeBytes(), truncated);
  }

  static Map<String, String> _lower(http.BaseResponse response) {
    final lowered = <String, String>{};
    response.headers.forEach((k, v) => lowered[k.toLowerCase()] = v);
    return lowered;
  }

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
    final (raw, truncated) = await _read(streamed, maxBytes);
    return HttpFetchResponse(
      finalUrl: streamed.request?.url ?? url,
      statusCode: streamed.statusCode,
      headers: _lower(streamed),
      body: utf8.decode(raw, allowMalformed: true),
      truncated: truncated,
    );
  }

  @override
  Future<HttpFetchBytes> getBytes(
    Uri url, {
    bool followRedirects = true,
    int maxBytes = 8 * 1024 * 1024,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final req = http.Request('GET', url);
    req.followRedirects = followRedirects;
    req.maxRedirects = 5;
    req.headers['user-agent'] = userAgent;
    req.headers['accept'] = 'application/x-bittorrent,application/octet-stream,*/*;q=0.5';
    if (headers != null) req.headers.addAll(headers);

    final streamed = await _client.send(req).timeout(timeout);
    final (raw, truncated) = await _read(streamed, maxBytes);
    return HttpFetchBytes(
      finalUrl: streamed.request?.url ?? url,
      statusCode: streamed.statusCode,
      headers: _lower(streamed),
      bytes: raw,
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
    final (raw, truncated) = await _read(streamed, maxBytes);
    return HttpFetchResponse(
      finalUrl: streamed.request?.url ?? url,
      statusCode: streamed.statusCode,
      headers: _lower(streamed),
      body: utf8.decode(raw, allowMalformed: true),
      truncated: truncated,
    );
  }

  @override
  void close() => _client.close();
}
