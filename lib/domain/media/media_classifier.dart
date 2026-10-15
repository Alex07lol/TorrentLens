import '../security/url_policy.dart';
import 'media_resource.dart';

/// Classifies a discovered URL using *multiple* signals. A filename extension
/// alone is treated as weak evidence (a `.mp4` may be an HTML error page); a
/// definitive MIME type or manifest structure outranks the extension.
class MediaClassifier {
  static const Map<String, MediaKind> _extKinds = {
    '.mp4': MediaKind.directVideo,
    '.m4v': MediaKind.directVideo,
    '.mkv': MediaKind.directVideo,
    '.webm': MediaKind.directVideo,
    '.mov': MediaKind.directVideo,
    '.avi': MediaKind.directVideo,
    '.ts': MediaKind.directVideo,
    '.mp3': MediaKind.directAudio,
    '.m4a': MediaKind.directAudio,
    '.aac': MediaKind.directAudio,
    '.flac': MediaKind.directAudio,
    '.ogg': MediaKind.directAudio,
    '.opus': MediaKind.directAudio,
    '.wav': MediaKind.directAudio,
    '.m3u8': MediaKind.hls,
    '.mpd': MediaKind.dash,
    '.srt': MediaKind.subtitle,
    '.vtt': MediaKind.subtitle,
    '.ass': MediaKind.subtitle,
    '.jpg': MediaKind.image,
    '.jpeg': MediaKind.image,
    '.png': MediaKind.image,
    '.gif': MediaKind.image,
    '.webp': MediaKind.image,
    '.avif': MediaKind.image,
    '.epub': MediaKind.epub,
    '.pdf': MediaKind.pdf,
    '.cbz': MediaKind.comicArchive,
    '.cbr': MediaKind.comicArchive,
    '.cb7': MediaKind.comicArchive,
    '.cbt': MediaKind.comicArchive,
    '.txt': MediaKind.webPage,
    '.md': MediaKind.webPage,
    '.html': MediaKind.webPage,
    '.htm': MediaKind.webPage,
    '.zip': MediaKind.archive,
    '.rar': MediaKind.archive,
    '.7z': MediaKind.archive,
    '.tar': MediaKind.archive,
    '.gz': MediaKind.archive,
    '.torrent': MediaKind.torrentFile,
  };

  static MediaKind kindForMime(String mime) {
    final m = mime.toLowerCase().split(';').first.trim();
    if (m == 'application/vnd.apple.mpegurl' ||
        m == 'application/x-mpegurl' ||
        m == 'audio/mpegurl') {
      return MediaKind.hls;
    }
    if (m == 'application/dash+xml') return MediaKind.dash;
    if (m == 'application/vnd.apple.mpegurl.audio') return MediaKind.hls;
    if (m == 'application/epub+zip') return MediaKind.epub;
    if (m == 'application/pdf') return MediaKind.pdf;
    if (m == 'application/x-bittorrent') return MediaKind.torrentFile;
    if (m == 'text/vtt') return MediaKind.subtitle;
    if (m == 'application/x-subrip' || m == 'text/srt') return MediaKind.subtitle;
    if (m.startsWith('video/')) return MediaKind.directVideo;
    if (m.startsWith('audio/')) return MediaKind.directAudio;
    if (m.startsWith('image/')) return MediaKind.image;
    if (m == 'text/html' || m == 'application/xhtml+xml') return MediaKind.webPage;
    return MediaKind.unsupported;
  }

  /// A definitive MIME type (one that maps to a real kind) outranks the URL
  /// extension. Otherwise the extension is used, falling back to `webPage` for
  /// http(s) URLs and `unsupported` for everything else.
  static MediaResource classify({
    required String url,
    String? mimeType,
    String? title,
    String? sourcePageUrl,
    bool hasWidevineData = false,
  }) {
    final evidence = <String>[];

    if (url.toLowerCase().startsWith('magnet:')) {
      evidence.add('magnet: scheme');
      return MediaResource(
        kind: MediaKind.magnet,
        url: url,
        title: title,
        sourcePageUrl: sourcePageUrl,
        action: MediaAction.addTorrent,
        evidence: evidence,
      );
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !UrlPolicy.allowedSchemes.contains(uri.scheme.toLowerCase())) {
      evidence.add('unsupported or unsafe scheme');
      return MediaResource(
        kind: MediaKind.unsupported,
        url: url,
        title: title,
        sourcePageUrl: sourcePageUrl,
        action: MediaAction.explainUnsupported,
        evidence: evidence,
      );
    }

    MediaKind? kind;
    if (mimeType != null && mimeType.trim().isNotEmpty) {
      final fromMime = kindForMime(mimeType);
      if (fromMime != MediaKind.unsupported) {
        kind = fromMime;
        evidence.add('MIME type $mimeType');
      } else {
        evidence.add('non-definitive MIME type $mimeType');
      }
    }

    final path = uri.path.toLowerCase();
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 ? path.substring(dot) : '';
    final fromExt = _extKinds[ext];
    if (kind == null && fromExt != null) {
      kind = fromExt;
      evidence.add('extension $ext');
    } else if (fromExt != null && kind != fromExt) {
      // MIME and extension disagree; keep the MIME-derived kind but record it.
      evidence.add('extension $ext conflicts with MIME type');
    }

    if (kind == null) {
      final isWeb = uri.scheme == 'http' || uri.scheme == 'https';
      kind = isWeb ? MediaKind.webPage : MediaKind.unsupported;
      evidence.add(isWeb ? 'no known extension; treating as a web page' : 'unknown kind');
    }

    if (hasWidevineData) {
      evidence.add('Widevine protection metadata present');
      return MediaResource(
        kind: MediaKind.drmProtected,
        url: url,
        title: title,
        sourcePageUrl: sourcePageUrl,
        mimeType: mimeType,
        action: MediaAction.evaluateDrm,
        evidence: evidence,
        isProtected: true,
      );
    }

    return MediaResource(
      kind: kind,
      url: url,
      title: title,
      sourcePageUrl: sourcePageUrl,
      mimeType: mimeType,
      action: actionForKind(kind),
      evidence: evidence,
    );
  }

  static MediaAction actionForKind(MediaKind kind) => switch (kind) {
        MediaKind.directVideo => MediaAction.playVideo,
        MediaKind.directAudio => MediaAction.playAudio,
        MediaKind.hls || MediaKind.dash => MediaAction.playStream,
        MediaKind.subtitle => MediaAction.attachSubtitle,
        MediaKind.image => MediaAction.openReaderPages,
        MediaKind.epub => MediaAction.openEpub,
        MediaKind.pdf => MediaAction.openPdf,
        MediaKind.comicArchive => MediaAction.openComic,
        MediaKind.torrentFile => MediaAction.inspectTorrent,
        MediaKind.magnet => MediaAction.addTorrent,
        MediaKind.htmlBundle => MediaAction.openWebsite,
        MediaKind.webPage => MediaAction.openWebsite,
        MediaKind.drmProtected => MediaAction.evaluateDrm,
        MediaKind.archive || MediaKind.unsupported => MediaAction.explainUnsupported,
      };
}
