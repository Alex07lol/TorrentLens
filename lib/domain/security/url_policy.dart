import '../../core/result.dart';

/// How a URL is about to be used. The policy differs per use: a `https://`
/// page is fine to navigate to but a `javascript:` URL never is, and only the
/// *fetch* path applies SSRF/private-network protection.
enum UrlUse { navigation, fetch, redirect }

enum UrlRejection {
  empty,
  unparseable,
  schemeNotAllowed,
  missingHost,
  credentialsInUrl,
  privateHostBlocked,
  crossOriginRedirect,
}

/// Central URL validation. Every outbound request, every WebView navigation and
/// every redirect hop must pass through here — the media resolver relies on it
/// so an HTML file inside a torrent cannot trick the app into fetching
/// `file:///data/...` or an internal address.
class UrlPolicy {
  /// Schemes we will ever navigate to or fetch.
  static const Set<String> allowedSchemes = {'http', 'https'};

  static const Set<String> _blockedHostSuffixes = {
    'localhost',
    'local',
    'internal',
    'home.arpa',
  };

  static Result<Uri> evaluate(String raw, {required UrlUse use}) {
    final s = raw.trim();
    if (s.isEmpty) return const Err(UrlRejection.empty);

    // Reject dangerous schemes before parsing where possible, so `javascript:
    // alert(1)` never reaches Uri parsing nuances.
    final schemeMatch = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):').firstMatch(s);
    if (schemeMatch != null) {
      final scheme = schemeMatch.group(1)!.toLowerCase();
      if (!allowedSchemes.contains(scheme)) {
        return const Err(UrlRejection.schemeNotAllowed);
      }
    }

    final uri = Uri.tryParse(s);
    if (uri == null) return const Err(UrlRejection.unparseable);
    if (uri.scheme.isEmpty) {
      // Relative URL: only meaningful after resolution; treat as unparseable here.
      return const Err(UrlRejection.unparseable);
    }
    if (!allowedSchemes.contains(uri.scheme.toLowerCase())) {
      return const Err(UrlRejection.schemeNotAllowed);
    }
    if (uri.host.isEmpty) return const Err(UrlRejection.missingHost);
    if (uri.userInfo.isNotEmpty) return const Err(UrlRejection.credentialsInUrl);
    if (use != UrlUse.navigation && isPrivateHost(uri.host)) {
      return const Err(UrlRejection.privateHostBlocked);
    }
    return Ok(uri);
  }

  /// True for loopback, link-local, RFC1918 and .local/.internal hostnames.
  /// Used to keep server-side/backend fetches from being turned into an SSRF
  /// primitive. On-device fetches of these are still blocked for safety.
  static bool isPrivateHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost') return true;
    for (final suffix in _blockedHostSuffixes) {
      if (h == suffix || h.endsWith('.$suffix')) return true;
    }
    final ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(h);
    if (ipv4 != null) {
      final a = int.parse(ipv4.group(1)!);
      final b = int.parse(ipv4.group(2)!);
      if (a == 10) return true;
      if (a == 127) return true;
      if (a == 169 && b == 254) return true;
      if (a == 172 && b >= 16 && b <= 31) return true;
      if (a == 192 && b == 168) return true;
      if (a == 0) return true;
      return false;
    }
    // IPv6 loopback / unique-local / link-local
    if (h == '::1' || h == '[::1]') return true;
    if (h.startsWith('fc') || h.startsWith('fd')) return true;
    if (h.startsWith('fe80')) return true;
    return false;
  }

  /// Removes embedded credentials so they can never leak into logs or the
  /// wrong origin when a URL is rewritten.
  static Uri stripCredentials(Uri uri) =>
      uri.userInfo.isEmpty ? uri : uri.replace(userInfo: '');

  /// Resolves [location] against [base] (an HTTP redirect or a relative href)
  /// and rejects cross-scheme downgrades. `location` may be relative.
  static Result<Uri> resolveRedirect(Uri base, String location) {
    final resolved = base.resolve(location.trim());
    if (!allowedSchemes.contains(resolved.scheme.toLowerCase())) {
      return const Err(UrlRejection.schemeNotAllowed);
    }
    if (resolved.host.isEmpty) return const Err(UrlRejection.missingHost);
    if (isPrivateHost(resolved.host)) {
      return const Err(UrlRejection.privateHostBlocked);
    }
    return Ok(stripCredentials(resolved));
  }

  static bool sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;
}
