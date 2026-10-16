import 'dart:typed_data';

import '../../domain/security/url_policy.dart';
import '../../domain/torrent/torrent_payload.dart';
import '../../integrations/media_resolver/http_fetcher.dart';

enum TorrentFetchError {
  unsafeUrl,
  tooManyRedirects,
  httpError,
  tooLarge,
  notATorrent,
  network,
}

class TorrentFetchResult {
  final Uint8List? bytes;
  final Uri? finalUrl;
  final TorrentFetchError? error;
  final String? message;

  const TorrentFetchResult({this.bytes, this.finalUrl, this.error, this.message});

  bool get ok => bytes != null;
}

/// Downloads a `.torrent` over HTTP(S) and hands back the **original bytes**.
///
/// This is deliberately separate from [MediaLinkResolver]: torrent files are
/// binary and every byte matters, so they are fetched with
/// [HttpFetcher.getBytes] and never pass through a text decode. Redirects are
/// followed one hop at a time and each hop is re-validated (a `.torrent` URL is
/// a classic SSRF and downgrade vector), and the body is structurally checked
/// so an HTML error page is reported as such instead of being fed to the
/// engine as a corrupt torrent.
class TorrentFileFetcher {
  /// A `.torrent` for a large multi-file release is a few hundred KiB; 8 MiB is
  /// already far beyond anything legitimate.
  static final int maxBytes = 8 * 1024 * 1024;

  static final int maxMiB = maxBytes ~/ (1024 * 1024);

  static const int maxRedirects = 5;

  /// Redirect statuses whose `Location` we follow ourselves.
  static const Set<int> _redirects = {301, 302, 303, 307, 308};

  final HttpFetcher fetcher;
  TorrentFileFetcher(this.fetcher);

  Future<TorrentFetchResult> fetch(String rawUrl) async {
    final initial = _initial(rawUrl);
    if (initial == null) {
      return const TorrentFetchResult(
        error: TorrentFetchError.unsafeUrl,
        message: 'That URL is not a safe http(s) destination to fetch from.',
      );
    }
    var current = initial;

    HttpFetchBytes response;
    var hops = 0;
    while (true) {
      try {
        response = await fetcher.getBytes(current, followRedirects: false, maxBytes: maxBytes);
      } catch (e) {
        return TorrentFetchResult(
          error: TorrentFetchError.network,
          message: 'Could not download the .torrent file: $e',
        );
      }

      if (!_redirects.contains(response.statusCode)) break;
      final location = response.location;
      if (location == null) {
        return TorrentFetchResult(
          error: TorrentFetchError.httpError,
          message: 'The server redirected (HTTP ${response.statusCode}) without a destination.',
        );
      }
      if (hops >= maxRedirects) {
        return TorrentFetchResult(
          error: TorrentFetchError.tooManyRedirects,
          message: 'The .torrent URL redirected more than $maxRedirects times.',
        );
      }
      final next = UrlPolicy.resolveRedirect(current, location);
      if (next.isErr) {
        return TorrentFetchResult(
          error: TorrentFetchError.unsafeUrl,
          message: 'The .torrent URL redirects to an unsafe destination '
              '(${next.errorOrNull()}).',
        );
      }
      current = next.valueOrNull!;
      hops++;
    }

    if (response.statusCode >= 400) {
      return TorrentFetchResult(
        error: TorrentFetchError.httpError,
        message: 'The server returned HTTP ${response.statusCode} for that .torrent URL.',
      );
    }
    if (response.truncated) {
      return TorrentFetchResult(
        error: TorrentFetchError.tooLarge,
        message: 'That download is larger than $maxMiB MiB, '
            'so it is not a .torrent file.',
      );
    }
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) {
      return TorrentFetchResult(
        error: TorrentFetchError.tooLarge,
        message: 'The server declared a body of $declared bytes, which is too '
            'large to be a .torrent file.',
      );
    }
    final contentType = response.contentType?.toLowerCase() ?? '';
    if (contentType.contains('text/html') || contentType.contains('application/json')) {
      return TorrentFetchResult(
        error: TorrentFetchError.notATorrent,
        message: 'That URL returned $contentType, not a .torrent file. '
            'It may be an error page or a link to a web page.',
      );
    }
    final problem = TorrentPayload.describeProblem(response.bytes);
    if (problem != null) {
      return TorrentFetchResult(error: TorrentFetchError.notATorrent, message: problem);
    }

    return TorrentFetchResult(bytes: response.bytes, finalUrl: current);
  }

  Uri? _initial(String rawUrl) {
    final evaluated = UrlPolicy.evaluate(rawUrl, use: UrlUse.fetch);
    return evaluated.valueOrNull;
  }
}
