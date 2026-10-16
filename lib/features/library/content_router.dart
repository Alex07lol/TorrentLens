import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/tabs/browser_tab.dart';
import '../../navigation/shell.dart';
import '../browser/tab_manager.dart';

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

  /// The tab type a [ContentKind] opens as.
  static BrowserTabType tabTypeFor(ContentKind kind) => switch (kind) {
        ContentKind.epub => BrowserTabType.epub,
        ContentKind.pdf => BrowserTabType.pdf,
        ContentKind.comic || ContentKind.image => BrowserTabType.comic,
        ContentKind.text => BrowserTabType.text,
        ContentKind.video || ContentKind.audio => BrowserTabType.player,
        ContentKind.html => BrowserTabType.web,
        ContentKind.unknown => BrowserTabType.home,
      };

  /// How a file is addressed inside a tab. Readers and the player use plain
  /// filesystem paths; an HTML bundle uses a `file://` URL because that is what
  /// the WebView needs, and the tab host tells the two apart by scheme.
  static String locationFor(ContentKind kind, String path) =>
      kind == ContentKind.html ? Uri.file(path).toString() : path;

  /// Opens [path] in the appropriate viewer, as a tab in the workspace.
  ///
  /// This used to push a route, which replaced whatever the user was looking at.
  /// Now the viewer becomes its own tab: the page (or explorer) it was opened
  /// from stays open behind it, and opening the same file twice focuses the
  /// existing tab instead of stacking duplicates.
  static void open(
    BuildContext context, {
    required String path,
    required String title,
    String? contentId,
  }) {
    final kind = kindOf(path);
    if (kind == ContentKind.unknown) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('TorrentLens has no viewer for this file type.\n'
            'You can still open it in another app from the Explorer.'),
      ));
      return;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    container.read(tabManagerProvider.notifier).openContent(
          type: tabTypeFor(kind),
          location: locationFor(kind, path),
          title: title,
          contentId: contentId,
        );
    // Bring the workspace forward so the user sees what they opened. The tab
    // they came from is untouched and can be switched back to.
    container.read(shellIndexProvider.notifier).set(ShellTab.tabs);
  }
}
