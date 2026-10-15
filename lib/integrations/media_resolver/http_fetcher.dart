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
