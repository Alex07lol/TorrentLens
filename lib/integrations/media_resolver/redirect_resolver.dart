import '../../core/result.dart';
import '../../domain/security/url_policy.dart';
import 'http_fetcher.dart';

class RedirectResult {
  final Uri finalUrl;
  final int statusCode;
  final HttpFetchResponse response;
  final List<Uri> hops;
  const RedirectResult(this.finalUrl, this.statusCode, this.response, this.hops);
}

enum RedirectError { tooManyHops, blockedDestination, unsafeRedirect, fetchFailed }

/// Follows HTTP redirects itself (rather than letting the client do it), so
/// every hop can be validated against [UrlPolicy]. This is what stops a
/// hostile page from redirecting the app to a private address or a `file:` URL.
class RedirectResolver {
  final HttpFetcher fetcher;
  final int maxHops;
  const RedirectResolver(this.fetcher, {this.maxHops = 5});

  Future<Result<RedirectResult>> resolve(Uri start, {int maxBytes = 512 * 1024}) async {
    var current = start;
    final hops = <Uri>[];

    for (var i = 0; i <= maxHops; i++) {
      final guard = UrlPolicy.evaluate(current.toString(), use: UrlUse.redirect);
      if (guard.isErr) return Err(guard.errorOrNull() ?? RedirectError.blockedDestination);

      HttpFetchResponse res;
      try {
        res = await fetcher.get(current, followRedirects: false, maxBytes: maxBytes);
      } catch (e) {
        return Err(RedirectError.fetchFailed);
      }

      final status = res.statusCode;
      final isRedirect = status >= 300 && status < 400;
      if (!isRedirect) {
        return Ok(RedirectResult(current, status, res, hops));
      }
      final location = res.location;
      if (location == null || location.isEmpty) {
        return Ok(RedirectResult(current, status, res, hops));
      }
      if (hops.length >= maxHops) return const Err(RedirectError.tooManyHops);

      final next = UrlPolicy.resolveRedirect(current, location);
      if (next.isErr) return Err(RedirectError.unsafeRedirect);
      current = next.valueOrNull!;
      hops.add(current);
    }
    return const Err(RedirectError.tooManyHops);
  }
}
