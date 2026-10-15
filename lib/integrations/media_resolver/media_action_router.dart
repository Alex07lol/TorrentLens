import '../../domain/media/media_resource.dart';

/// The concrete in-app destination a discovered resource should open.
enum RouteTarget {
  player,
  attachSubtitle,
  readerPages,
  epubReader,
  pdfViewer,
  comicViewer,
  addTorrent,
  torrentInspector,
  webSandbox,
  externalBrowser,
  drmFlow,
  unsupportedDialog,
}

class RoutedAction {
  final MediaResource resource;
  final RouteTarget target;
  /// True whenever opening the resource would fetch bytes or leave the app.
  /// Nothing is downloaded implicitly.
  final bool requiresConfirmation;
  final String? note;
  const RoutedAction(this.resource, this.target,
      {this.requiresConfirmation = false, this.note});
}

/// Maps a classified [MediaResource] to an in-app destination.
class MediaActionRouter {
  static RoutedAction route(MediaResource r) => switch (r.kind) {
        MediaKind.directVideo => RoutedAction(r, RouteTarget.player,
            note: 'Video playback (hardware decoding preferred).'),
        MediaKind.directAudio => RoutedAction(r, RouteTarget.player, note: 'Audio playback.'),
        MediaKind.hls || MediaKind.dash => RoutedAction(r, RouteTarget.player,
            note: 'Adaptive stream; the player reads the manifest.'),
        MediaKind.subtitle => RoutedAction(r, RouteTarget.attachSubtitle,
            note: 'Attach to the current playback session.'),
        MediaKind.image => RoutedAction(r, RouteTarget.readerPages),
        MediaKind.epub =>
          RoutedAction(r, RouteTarget.epubReader, requiresConfirmation: true),
        MediaKind.pdf => RoutedAction(r, RouteTarget.pdfViewer, requiresConfirmation: true),
        MediaKind.comicArchive =>
          RoutedAction(r, RouteTarget.comicViewer, requiresConfirmation: true),
        MediaKind.torrentFile =>
          RoutedAction(r, RouteTarget.torrentInspector, requiresConfirmation: true),
        MediaKind.magnet =>
          RoutedAction(r, RouteTarget.addTorrent, requiresConfirmation: true),
        MediaKind.htmlBundle || MediaKind.webPage =>
          RoutedAction(r, RouteTarget.webSandbox, requiresConfirmation: true),
        MediaKind.archive => RoutedAction(r, RouteTarget.unsupportedDialog,
            note: 'Archive browsing is available from the content explorer.'),
        MediaKind.drmProtected => RoutedAction(r, RouteTarget.drmFlow),
        MediaKind.unsupported => RoutedAction(r, RouteTarget.unsupportedDialog),
      };
}
