import 'dart:typed_data';

/// What a downloaded `.torrent` payload actually looks like.
///
/// A `.torrent` file is bencoded binary data, and it *must* be handed to the
/// engine byte-for-byte. The checks here are deliberately cheap and structural:
/// they catch the failure modes that actually happen — a server answering with
/// an HTML error page, a JSON API response, a truncated body — without trying
/// to be a full bencode parser.
class TorrentPayload {
  /// Bencode dictionaries start with `d` (0x64). Everything else is either a
  /// different encoding or a wrong-response-body.
  static const int _dictStart = 0x64;

  /// Smallest plausible `.torrent`: a dict with an announce URL and an empty
  /// info dict. Real files are far larger; this only rejects obviously empty
  /// or stub responses.
  static const int minPlausibleBytes = 20;

  static bool looksBencoded(Uint8List bytes) =>
      bytes.isNotEmpty && bytes.first == _dictStart;

  /// True for bodies that are clearly a web/API response rather than a torrent:
  /// HTML, JSON, XML or anything else that starts with printable text that is
  /// not a bencode dict.
  static bool looksLikeText(Uint8List bytes) {
    var i = 0;
    // A BOM or leading whitespace is itself disqualifying: bencode has none.
    while (i < bytes.length && (bytes[i] == 0xEF || bytes[i] == 0xBB || bytes[i] == 0xBF ||
        bytes[i] == 0x20 || bytes[i] == 0x09 || bytes[i] == 0x0A || bytes[i] == 0x0D)) {
      i++;
    }
    if (i >= bytes.length) return true;
    final b = bytes[i];
    return b != _dictStart && b >= 0x20 && b < 0x7F;
  }

  /// Human-readable reason the payload cannot be a torrent, or null when it
  /// passes every structural check.
  static String? describeProblem(Uint8List bytes) {
    if (bytes.isEmpty) return 'The server returned an empty response.';
    if (bytes.length < minPlausibleBytes) {
      return 'The response is only ${bytes.length} bytes; that is too small to be '
          'a .torrent file.';
    }
    if (looksLikeText(bytes)) {
      return 'The server returned a web page or API response, not a .torrent file.';
    }
    if (!looksBencoded(bytes)) {
      return 'The response is not bencoded data, so it is not a .torrent file.';
    }
    return null;
  }
}
