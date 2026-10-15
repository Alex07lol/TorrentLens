// Arguments passed through GoRouter `extra` to detail screens.

import '../domain/torrent/streaming.dart';

class PlayerArgs {
  final String source;
  final String title;
  final String? mimeType;
  final bool isLocalFile;
  final String? subtitlePath;
  final String? contentId;

  /// Set to play a file while it is still downloading. The player then reads the
  /// partial file at [StreamingTarget.localPath] and the torrent engine
  /// prioritises the pieces ahead of the playhead.
  final StreamingTarget? stream;

  const PlayerArgs({
    required this.source,
    required this.title,
    this.mimeType,
    this.isLocalFile = false,
    this.subtitlePath,
    this.contentId,
    this.stream,
  });
}

class ReaderArgs {
  final String path;
  final String title;
  final String? contentId;
  const ReaderArgs({required this.path, required this.title, this.contentId});
}

class WebSandboxArgs {
  final String title;
  final Uri? url;
  final String? localHtmlPath;
  final bool allowJavascript;
  const WebSandboxArgs({
    required this.title,
    this.url,
    this.localHtmlPath,
    this.allowJavascript = false,
  });
}
