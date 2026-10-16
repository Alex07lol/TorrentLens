import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/media/drm.dart';
import '../../domain/media/media_resource.dart';
import '../../domain/tabs/browser_tab.dart';
import '../../integrations/media_resolver/media_action_router.dart';
import '../../integrations/media_resolver/media_link_resolver.dart';
import '../browser/tab_manager.dart';
import '../downloads/torrent_import_service.dart';

/// The resource panel: every media/torrent/subtitle link discovered on a page,
/// with the action TorrentLens will take. Nothing is downloaded implicitly.
Future<void> showDiscoveredResources(
  BuildContext context,
  LinkResolutionResult result, {
  required String pageTitle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (ctx, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Discovered resources', style: Theme.of(ctx).textTheme.titleMedium),
            Text('${result.resources.length} link(s) on $pageTitle',
                style: Theme.of(ctx).textTheme.bodySmall),
            if (result.warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(result.warnings.join('\n'),
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: result.resources.isEmpty
                  ? const Center(child: Text('No routable links were found on this page.'))
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: result.resources.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final r = result.resources[i];
                        final routed = MediaActionRouter.route(r);
                        return ListTile(
                          leading: Icon(_iconFor(r.kind)),
                          title: Text(r.title ?? r.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${r.kind.name} · ${r.evidence.join(', ')}',
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              if (r.isProtected)
                                Text('Protected stream — playback requires provider authorisation',
                                    style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 12)),
                            ],
                          ),
                          trailing: TextButton(
                            onPressed: () => _act(ctx, r),
                            child: Text(routed.requiresConfirmation ? 'Open…' : 'Open'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

IconData _iconFor(MediaKind kind) => switch (kind) {
      MediaKind.directVideo => Icons.movie_outlined,
      MediaKind.directAudio => Icons.music_note_outlined,
      MediaKind.hls || MediaKind.dash => Icons.stream,
      MediaKind.subtitle => Icons.subtitles_outlined,
      MediaKind.image => Icons.image_outlined,
      MediaKind.epub => Icons.menu_book_outlined,
      MediaKind.pdf => Icons.picture_as_pdf_outlined,
      MediaKind.comicArchive => Icons.auto_stories_outlined,
      MediaKind.torrentFile => Icons.description_outlined,
      MediaKind.magnet => Icons.link,
      MediaKind.htmlBundle || MediaKind.webPage => Icons.public,
      MediaKind.drmProtected => Icons.lock_outline,
      _ => Icons.help_outline,
    };

/// Opens [r] in the right place. Player and web resources become their own tabs,
/// so the page they were found on stays exactly where it was.
void _act(BuildContext context, MediaResource r) {
  final routed = MediaActionRouter.route(r);
  final container = ProviderScope.containerOf(context, listen: false);
  final tabs = container.read(tabManagerProvider.notifier);
  final title = r.title ?? r.url;

  switch (routed.target) {
    case RouteTarget.player:
      Navigator.pop(context);
      tabs.openContent(
        type: BrowserTabType.player,
        location: r.url,
        title: title,
      );
    case RouteTarget.addTorrent:
    case RouteTarget.torrentInspector:
      Navigator.pop(context);
      _addTorrent(context, container, r);
    case RouteTarget.webSandbox:
      final url = Uri.tryParse(r.url);
      Navigator.pop(context);
      if (url == null) {
        _say(context, 'That link is not a usable page address.');
        return;
      }
      tabs.openWeb(url, title: title);
    case RouteTarget.drmFlow:
      Navigator.pop(context);
      _drmFlow(context, r);
    case RouteTarget.externalBrowser:
    case RouteTarget.attachSubtitle:
      Navigator.pop(context);
      _say(context, 'This resource needs a playback session that is not active right now.');
    default:
      Navigator.pop(context);
      _say(context, '${r.kind.name} resources are opened from the Library or Explorer.');
  }
}

/// Magnets and `.torrent` URLs go through the same import service as everywhere
/// else, then get a tab of their own.
Future<void> _addTorrent(
  BuildContext context,
  ProviderContainer container,
  MediaResource r,
) async {
  final service = TorrentImportService(container.read(servicesProvider));
  final result = r.url.toLowerCase().startsWith('magnet:')
      ? await service.addMagnet(r.url)
      : await service.addTorrentUrl(r.url);
  if (!context.mounted) return;
  if (!result.ok) {
    _say(context, result.error ?? 'That link could not be added.');
    return;
  }
  final hash = result.infoHash;
  if (hash != null) {
    container.read(tabManagerProvider.notifier).openTorrent(
          infoHash: hash,
          title: r.title ?? 'Torrent ${hash.substring(0, 8)}',
          taskId: result.taskId,
        );
  }
  _say(context, 'Torrent added. Metadata is resolving in Downloads.');
}

void _say(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

/// Asks the configured [AuthorizedPlaybackAdapter] what would actually happen.
///
/// The answer is reported verbatim. With no provider wired up the adapter
/// returns `providerNotConfigured`, so the app never implies that protected
/// content will play. TorrentLens does not acquire or bypass licenses.
Future<void> _drmFlow(BuildContext context, MediaResource r) async {
  final services =
      ProviderScope.containerOf(context, listen: false).read(servicesProvider);
  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri.tryParse(r.url);
  if (uri == null) {
    messenger.showSnackBar(const SnackBar(
      content: Text('This protected resource has no usable URL.'),
    ));
    return;
  }

  // The classifier's own evidence is the manifest/header text we have.
  final assessment = DrmCapabilityDetector.assess(
    manifestText: r.evidence.join(' '),
    headers: r.mimeType == null ? null : {'content-type': r.mimeType!},
  );

  final result = await services.authorizedPlayback.authorize(
    DrmPlaybackRequest(source: uri, assessment: assessment, assetId: r.title),
  );

  messenger.showSnackBar(SnackBar(
    content: Text(result.message),
    duration: const Duration(seconds: 6),
  ));
}
