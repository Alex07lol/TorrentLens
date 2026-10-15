import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../domain/media/drm.dart';
import '../../domain/media/media_resource.dart';
import '../../integrations/media_resolver/media_action_router.dart';
import '../../integrations/media_resolver/media_link_resolver.dart';
import '../../navigation/route_args.dart';

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

void _act(BuildContext context, MediaResource r) {
  final routed = MediaActionRouter.route(r);
  switch (routed.target) {
    case RouteTarget.player:
      context.push('/player', extra: PlayerArgs(source: r.url, title: r.title ?? r.url, mimeType: r.mimeType));
    case RouteTarget.addTorrent:
    case RouteTarget.torrentInspector:
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Magnet/torrent links are added from the Downloads tab.'),
        action: SnackBarAction(label: 'Later', onPressed: () {}),
      ));
    case RouteTarget.webSandbox:
      context.push('/web', extra: WebSandboxArgs(title: r.title ?? r.url, url: Uri.tryParse(r.url)));
    case RouteTarget.drmFlow:
      Navigator.pop(context);
      _drmFlow(context, r);
    case RouteTarget.externalBrowser:
    case RouteTarget.attachSubtitle:
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This resource needs a playback session that is not active right now.'),
      ));
    default:
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${r.kind.name} resources are opened from the Library or Explorer.'),
      ));
  }
}

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
