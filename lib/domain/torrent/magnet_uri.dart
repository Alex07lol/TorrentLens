import 'info_hash.dart';

/// Why a magnet URI could not be parsed. Values are surfaced to the UI so the
/// user gets a specific reason instead of a generic "invalid link".
enum MagnetParseError {
  notAMagnet,
  missingInfoHash,
  unsupportedHash,
  invalidInfoHash,
  duplicateInfoHash,
}

class MagnetUriParseException implements Exception {
  final MagnetParseError error;
  final String message;
  const MagnetUriParseException(this.error, this.message);
  @override
  String toString() => 'MagnetUriParseException($error): $message';
}

/// A parsed `magnet:` URI.
class MagnetUri {
  final String raw;
  final InfoHash infoHash;
  /// `dn` — the display name, if supplied.
  final String? displayName;
  /// `tr` — announce trackers (may repeat).
  final List<String> trackers;
  /// `ws` — web seed / HTTP sources.
  final List<String> webSeeds;
  /// Every `xt` value, in order (v1 `urn:btih:` and v2 `urn:btmh:`).
  final List<String> exactTopics;

  const MagnetUri({
    required this.raw,
    required this.infoHash,
    required this.displayName,
    required this.trackers,
    required this.webSeeds,
    required this.exactTopics,
  });

  static const Set<String> _allowedSchemes = {'magnet'};

  static bool looksLikeMagnet(String input) =>
      input.trim().toLowerCase().startsWith('magnet:');

  static MagnetUri parse(String input) {
    final trimmed = input.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !_allowedSchemes.contains(uri.scheme.toLowerCase())) {
      throw const MagnetUriParseException(
          MagnetParseError.notAMagnet, 'Not a magnet: URI');
    }

    // magnet query parameters are case-insensitive and may repeat.
    final params = <String, List<String>>{};
    for (final pair in uri.query.split('&')) {
      if (pair.isEmpty) continue;
      final idx = pair.indexOf('=');
      final key = (idx < 0 ? pair : pair.substring(0, idx)).toLowerCase();
      final value = idx < 0 ? '' : Uri.decodeComponent(pair.substring(idx + 1));
      params.putIfAbsent(key, () => <String>[]).add(value);
    }

    final xts = params['xt'] ?? const <String>[];
    if (xts.isEmpty) {
      throw const MagnetUriParseException(
          MagnetParseError.missingInfoHash, 'magnet link has no xt parameter');
    }

    InfoHash? v1;
    var sawV2 = false;
    for (final xt in xts) {
      final lower = xt.toLowerCase();
      if (lower.startsWith('urn:btih:')) {
        if (v1 != null) {
          throw const MagnetUriParseException(MagnetParseError.duplicateInfoHash,
              'magnet link contains more than one v1 info-hash');
        }
        v1 = InfoHash.tryParse(xt.substring('urn:btih:'.length));
        if (v1 == null) {
          throw const MagnetUriParseException(MagnetParseError.invalidInfoHash,
              'xt is not a valid 20-byte info-hash');
        }
      } else if (lower.startsWith('urn:btmh:')) {
        sawV2 = true;
      } else {
        throw MagnetUriParseException(MagnetParseError.unsupportedHash,
            'unsupported exact topic: $xt');
      }
    }

    final hash = v1;
    if (hash == null) {
      if (sawV2) {
        throw const MagnetUriParseException(MagnetParseError.unsupportedHash,
            'BitTorrent v2 (btmh) magnets are not supported by the selected engine');
      }
      throw const MagnetUriParseException(
          MagnetParseError.missingInfoHash, 'magnet link has no v1 info-hash');
    }

    return MagnetUri(
      raw: trimmed,
      infoHash: hash,
      displayName: (params['dn']?.isNotEmpty ?? false) ? params['dn']!.first : null,
      trackers: List.unmodifiable(params['tr'] ?? const <String>[]),
      webSeeds: List.unmodifiable(params['ws'] ?? const <String>[]),
      exactTopics: List.unmodifiable(xts),
    );
  }

  static MagnetUri? tryParse(String input) {
    try {
      return parse(input);
    } on MagnetUriParseException {
      return null;
    }
  }
}
