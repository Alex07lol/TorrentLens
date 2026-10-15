import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../navigation/route_args.dart';

enum ContentKind { epub, pdf, comic, text, image, video, audio, html, unknown }

/// Decides which in-app viewer opens a local file, based purely on its name.
/// Unknown types are explained rather than silently ignored.
class ContentRouter {
  static const Map<String, ContentKind> _extensions = {
    '.epub': ContentKind.epub,
    '.pdf': ContentKind.pdf,
    '.cbz': ContentKind.comic,
    '.cbr': ContentKind.comic,
    '.cb7': ContentKind.comic,
    '.cbt': ContentKind.comic,
    '.txt': ContentKind.text,
    '.md': ContentKind.text,
    '.markdown': ContentKind.text,
    '.jpg': ContentKind.image,
    '.jpeg': ContentKind.image,
    '.png': ContentKind.image,
    '.gif': ContentKind.image,
    '.webp': ContentKind.image,
    '.mp4': ContentKind.video,
    '.mkv': ContentKind.video,
    '.webm': ContentKind.video,
    '.m4v': ContentKind.video,
    '.mov': ContentKind.video,
    '.mp3': ContentKind.audio,
    '.m4a': ContentKind.audio,
    '.flac': ContentKind.audio,
    '.ogg': ContentKind.audio,
    '.opus': ContentKind.audio,
    '.wav': ContentKind.audio,
    '.html': ContentKind.html,
    '.htm': ContentKind.html,
    '.xhtml': ContentKind.html,
  };

  static ContentKind kindOf(String path) {
    final lower = path.toLowerCase();
    for (final e in _extensions.entries) {
      if (lower.endsWith(e.key)) return e.value;
    }
    return ContentKind.unknown;
  }

  static String labelFor(ContentKind kind) => switch (kind) {
        ContentKind.epub => 'EPUB book',
        ContentKind.pdf => 'PDF document',
        ContentKind.comic => 'Comic archive',
        ContentKind.text => 'Text document',
        ContentKind.image => 'Image',
        ContentKind.video => 'Video',
        ContentKind.audio => 'Audio',
        ContentKind.html => 'Web page',
        ContentKind.unknown => 'Unsupported file',
      };

  /// Opens [path] in the appropriate viewer.
  static void open(BuildContext context, {required String path, required String title, String? contentId}) {
    switch (kindOf(path)) {
      case ContentKind.epub:
        context.push('/reader/epub', extra: ReaderArgs(path: path, title: title, contentId: contentId));
      case ContentKind.pdf:
        context.push('/reader/pdf', extra: ReaderArgs(path: path, title: title, contentId: contentId));
      case ContentKind.comic:
      case ContentKind.image:
        context.push('/reader/comic', extra: ReaderArgs(path: path, title: title, contentId: contentId));
      case ContentKind.text:
        context.push('/reader/text', extra: ReaderArgs(path: path, title: title, contentId: contentId));
      case ContentKind.video:
      case ContentKind.audio:
        context.push('/player',
            extra: PlayerArgs(source: path, title: title, isLocalFile: true, contentId: contentId));
      case ContentKind.html:
        context.push('/web', extra: WebSandboxArgs(title: title, localHtmlPath: path));
      case ContentKind.unknown:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('TorrentLens has no viewer for this file type.\n'
              'You can still open it in another app from the Explorer.'),
        ));
    }
  }
}
