import '../security/url_policy.dart';

/// What the user typed into the address bar, resolved.
class AddressParse {
  final Uri? url;
  final String? rejection;
  final bool isSearch;

  /// True when the input was a magnet link, which the address bar hands to the
  /// add-torrent flow instead of navigation.
  final bool isMagnet;

  const AddressParse({this.url, this.rejection, this.isSearch = false, this.isMagnet = false});

  bool get ok => url != null;

  static const AddressParse notAMagnet = AddressParse(isMagnet: true);
}

/// Turns address-bar text into a destination.
///
/// Pure and unit-tested: it decides whether the input is a URL, a search query
/// or invalid, normalizes the common "example.com" case to https, and refuses
/// dangerous schemes, embedded credentials and private/loopback destinations.
/// Insecure `http` is allowed (some torrent-provided sites are http-only) but
/// flagged so the UI can say so.
class BrowserAddress {
  static const String defaultSearchTemplate = 'https://duckduckgo.com/?q=%s';

  static AddressParse parse(String raw, {String searchTemplate = defaultSearchTemplate}) {
    final input = raw.trim();
    if (input.isEmpty) return const AddressParse(rejection: 'Enter an address or a search term.');

    final lower = input.toLowerCase();
    if (lower.startsWith('magnet:')) return AddressParse.notAMagnet;
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(input) &&
        !lower.startsWith('http://') &&
        !lower.startsWith('https://')) {
      return const AddressParse(
          rejection: 'Only http and https pages can be opened in a tab.');
    }

    final direct = _tryAbsolute(input);
    if (direct != null) return direct;

    // "example.com/path" — the scheme most users omit.
    if (!input.contains(' ') && input.contains('.')) {
      final withScheme = _tryAbsolute('https://$input');
      if (withScheme != null) return withScheme;
    }

    return AddressParse(url: _searchUrl(input, searchTemplate), isSearch: true);
  }

  static AddressParse? _tryAbsolute(String candidate) {
    // `fetch` is the strictest use: it applies the same private-network rules
    // the WebView navigation policy enforces, so the address bar cannot accept
    // something the viewer will then refuse.
    final evaluated = UrlPolicy.evaluate(candidate, use: UrlUse.fetch);
    if (evaluated.isErr) {
      final reason = evaluated.errorOrNull();
      return switch (reason) {
        UrlRejection.schemeNotAllowed =>
          const AddressParse(rejection: 'That page scheme is not supported.'),
        UrlRejection.credentialsInUrl =>
          const AddressParse(rejection: 'Addresses with embedded usernames or passwords are refused.'),
        UrlRejection.missingHost => const AddressParse(rejection: 'That address has no host.'),
        UrlRejection.privateHostBlocked => const AddressParse(
            rejection: 'Requests to private, loopback and link-local addresses are blocked.'),
        UrlRejection.empty || UrlRejection.unparseable => null,
        _ => const AddressParse(rejection: 'That address could not be understood.'),
      };
    }
    return AddressParse(url: evaluated.valueOrNull);
  }

  static Uri? _searchUrl(String query, String template) {
    final encoded = Uri.encodeQueryComponent(query);
    final uri = Uri.tryParse(template.replaceAll('%s', encoded));
    return (uri != null && uri.hasScheme && uri.host.isNotEmpty) ? uri : null;
  }

  /// Display form of a URL: credentials stripped, and everything but the origin
  /// hidden when [full] is false.
  static String display(Uri url, {bool full = true}) {
    final clean = UrlPolicy.stripCredentials(url);
    if (full || clean.path.isEmpty || clean.path == '/') {
      return clean.toString();
    }
    return '${clean.origin}/…';
  }
}
