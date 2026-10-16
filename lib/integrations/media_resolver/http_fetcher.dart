import 'dart:typed_data';

/// Minimal HTTP abstraction so the resolver can be tested without a network.
class HttpFetchResponse {
  final Uri finalUrl;
  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final bool truncated;
  const HttpFetchResponse({
    required this.finalUrl,
    required this.statusCode,
    required this.headers,
    required this.body,
    this.truncated = false,
  });

  String? get contentType => headers['content-type'];
  String? get location => headers['location'];
}

/// A raw-body response.
///
/// Binary payloads such as `.torrent` files must reach the torrent engine
/// exactly as they arrived. Decoding them as text and re-encoding loses every
/// byte that is not valid UTF-8, which silently corrupts the file, so those
/// paths use [HttpFetcher.getBytes] instead of [HttpFetcher.get].
class HttpFetchBytes {
  final Uri finalUrl;
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bytes;

  /// True when the body hit [maxBytes] and was cut off, i.e. the response is
  /// incomplete and must not be treated as a whole file.
  final bool truncated;

  const HttpFetchBytes({
    required this.finalUrl,
    required this.statusCode,
    required this.headers,
    required this.bytes,
    this.truncated = false,
  });

  String? get contentType => headers['content-type'];
  String? get location => headers['location'];
  int? get contentLength => int.tryParse(headers['content-length'] ?? '');
}

abstract class HttpFetcher {
  /// Performs a GET. [maxBytes] bounds the response so a hostile server cannot
  /// exhaust memory. When [followRedirects] is false the caller (the
  /// [RedirectResolver]) is responsible for hop-by-hop validation.
  Future<HttpFetchResponse> get(
    Uri url, {
    bool followRedirects = true,
    int maxBytes = 512 * 1024,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
  });

  /// GET whose body is kept as bytes. Same bounds and redirect semantics as
  /// [get]. The default throws so read-only fakes stay small;
  /// [HttpFetcherImpl] overrides it.
  Future<HttpFetchBytes> getBytes(
    Uri url, {
    bool followRedirects = true,
    int maxBytes = 8 * 1024 * 1024,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
  }) {
    throw UnsupportedError('binary GET is not implemented by this fetcher');
  }

  /// Releases any pooled connections. A no-op for read-only fakes.
  void close() {}

  /// POSTs a JSON body. Concrete default throws so read-only fakes stay small;
  /// [HttpFetcherImpl] overrides it.
  Future<HttpFetchResponse> post(
    Uri url, {
    Object? body,
    int maxBytes = 512 * 1024,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
  }) {
    throw UnsupportedError('POST is not implemented by this fetcher');
  }
}
