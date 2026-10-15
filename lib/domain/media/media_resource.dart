/// Every kind of resource the Media Link Resolver can surface, plus where the
/// evidence for the classification came from.
enum MediaKind {
  directVideo,
  directAudio,
  hls,
  dash,
  subtitle,
  image,
  epub,
  pdf,
  comicArchive,
  torrentFile,
  magnet,
  webPage,
  htmlBundle,
  archive,
  drmProtected,
  unsupported,
}

/// The action the router should take for a discovered resource.
enum MediaAction {
  playVideo,
  playAudio,
  playStream,
  attachSubtitle,
  openReaderPages,
  openEpub,
  openPdf,
  openComic,
  addTorrent,
  inspectTorrent,
  openWebsite,
  openInBrowser,
  evaluateDrm,
  explainUnsupported,
}

class MediaResource {
  final MediaKind kind;
  final String url;
  /// Human-facing label, usually the anchor text or the file name.
  final String? title;
  /// The page this resource was discovered on, for provenance.
  final String? sourcePageUrl;
  final String? mimeType;
  final MediaAction action;
  /// Human-readable reasons the classifier chose this kind.
  final List<String> evidence;
  final bool isProtected;

  const MediaResource({
    required this.kind,
    required this.url,
    required this.action,
    this.title,
    this.sourcePageUrl,
    this.mimeType,
    this.evidence = const [],
    this.isProtected = false,
  });

  @override
  String toString() => 'MediaResource($kind -> $url)';
}
