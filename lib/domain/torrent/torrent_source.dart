import 'info_hash.dart';

enum TorrentSourceKind { magnet, torrentFile, torrentUrl, publisherManifest }

/// How a torrent task was created. `publisherManifest` sources additionally
/// carry the publisher identity so provenance survives into the library.
class TorrentSource {
  final TorrentSourceKind kind;
  final String raw;
  final InfoHash? infoHash;
  final String? publisherId;
  final String? sourcePageUrl;

  const TorrentSource({
    required this.kind,
    required this.raw,
    this.infoHash,
    this.publisherId,
    this.sourcePageUrl,
  });

  /// Classifies an arbitrary imported string. Validation is intentionally
  /// permissive here (it feeds the import UI); strong validation happens in the
  /// link router before anything is fetched.
  static TorrentSource classify(String raw) {
    final trimmed = raw.trim();
    if (trimmed.toLowerCase().startsWith('magnet:')) {
      return TorrentSource(
        kind: TorrentSourceKind.magnet,
        raw: trimmed,
        infoHash: InfoHash.tryParse(() {
          final m = RegExp(r'[?&]xt=urn:btih:([A-Za-z2-7]{32}|[0-9a-fA-F]{40})',
                  caseSensitive: false)
              .firstMatch(trimmed);
          return m?.group(1) ?? '';
        }()),
      );
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      if (uri.path.toLowerCase().endsWith('.torrent')) {
        return TorrentSource(kind: TorrentSourceKind.torrentUrl, raw: trimmed);
      }
    }
    return TorrentSource(kind: TorrentSourceKind.torrentFile, raw: trimmed);
  }
}
