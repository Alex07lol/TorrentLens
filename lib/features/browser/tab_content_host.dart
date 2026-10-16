import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../app/services.dart';
import '../../design_system/components.dart';
import '../../domain/models/torrent_task.dart';
import '../../domain/tabs/browser_tab.dart';
import '../../navigation/route_args.dart';
import '../../util/format.dart';
import '../cloud_sync/cloud_sync_screen.dart';
import '../explorer/explorer_screen.dart';
import '../library/content_router.dart';
import '../player/player_screen.dart';
import '../reader/comic_reader_screen.dart';
import '../reader/epub_reader_screen.dart';
import '../reader/pdf_reader_screen.dart';
import '../reader/text_reader_screen.dart';
import '../subscriptions/subscriptions_screen.dart';
import '../web_sandbox/web_sandbox_screen.dart';
import 'new_tab_view.dart';
import 'tab_manager.dart';

/// Renders the inside of one tab.
///
/// It never owns navigation: every state change it observes is pushed into the
/// [TabManager] against *this* tab's id, which is what keeps two tabs from
/// overwriting each other's titles, spinners or errors.
class TabContentHost extends ConsumerWidget {
  final BrowserTab tab;

  /// Called when the user asks to reload this tab: the workspace recreates the
  /// tab's content with a fresh key.
  final VoidCallback onReload;

  const TabContentHost({super.key, required this.tab, required this.onReload});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tab.error != null) {
      return TabRecoveryView(
        tab: tab,
        onReload: onReload,
        onClose: () => ref.read(tabManagerProvider.notifier).close(tab.id),
      );
    }
    return switch (tab.type) {
      BrowserTabType.home => const NewTabView(),
      BrowserTabType.web => _web(context, ref),
      BrowserTabType.torrent => _TorrentTabView(tab: tab),
      BrowserTabType.explorer => const ExplorerScreen(),
      BrowserTabType.subscription => const SubscriptionsScreen(),
      BrowserTabType.cloud => const CloudSyncScreen(),
      BrowserTabType.player => PlayerScreen(
          args: PlayerArgs(
            source: tab.location,
            title: tab.title,
            isLocalFile: !tab.location.startsWith('http'),
            contentId: tab.contentId,
          ),
        ),
      BrowserTabType.epub => EpubReaderScreen(args: _readerArgs()),
      BrowserTabType.pdf => PdfReaderScreen(args: _readerArgs()),
      BrowserTabType.comic => ComicReaderScreen(args: _readerArgs()),
      BrowserTabType.text => TextReaderScreen(args: _readerArgs()),
      BrowserTabType.media => _MediaTabView(tab: tab),
    };
  }

  ReaderArgs _readerArgs() =>
      ReaderArgs(path: tab.location, title: tab.title, contentId: tab.contentId);

  Widget _web(BuildContext context, WidgetRef ref) {
    final uri = Uri.tryParse(tab.location);
    final isLocal = uri != null && uri.scheme == 'file';
    return WebSandboxScreen(
      args: WebSandboxArgs(
        title: tab.title,
        url: isLocal ? null : uri,
        localHtmlPath: isLocal ? uri.toFilePath() : null,
        // A page the user navigated to needs scripts to be useful; content
        // unpacked from a torrent does not, and starts with them off.
        allowJavascript: !isLocal,
        untrustedContent: isLocal,
      ),
      onPageChanged: (url, title) {
        final manager = ref.read(tabManagerProvider.notifier);
        final commanded = url == tab.location;
        manager.navigate(
          tabId: tab.id,
          location: url,
          // Keep the tab's own title when the page has none, so a title never
          // degrades to an empty string mid-load.
          title: (title != null && title.trim().isNotEmpty) ? title : tab.title,
          type: BrowserTabType.web,
          // A page the WebView reported on its own is a real navigation and
          // belongs in history; the page we asked it to load is already there.
          push: !commanded,
        );
      },
      onLoadingChanged: (loading) =>
          ref.read(tabManagerProvider.notifier).setLoading(tab.id, loading),
    );
  }
}

/// What a tab shows when its content cannot be restored.
///
/// This is the difference between "a useful recovery screen" and "a blank tab":
/// the user sees what went wrong, what the tab pointed at, and what to do next.
class TabRecoveryView extends StatelessWidget {
  final BrowserTab tab;
  final VoidCallback onReload;
  final VoidCallback onClose;

  const TabRecoveryView({
    super.key,
    required this.tab,
    required this.onReload,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ErrorView(
            message: '${tab.error}\n\n'
                'This tab was: ${tab.title.isEmpty ? tab.type.name : tab.title}\n'
                '${tab.location.isEmpty ? '' : tab.location}',
            onRetry: onReload,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextButton.icon(
            onPressed: onClose,
            icon: const Icon(Icons.close),
            label: const Text('Close this tab'),
          ),
        ),
      ],
    );
  }
}

/// A tab showing one torrent task: its real state, its files, and what can be
/// opened. Everything comes from the database, so it survives a restart; if the
/// task is gone the tab says so instead of showing stale data.
class _TorrentTabView extends ConsumerStatefulWidget {
  final BrowserTab tab;
  const _TorrentTabView({required this.tab});

  @override
  ConsumerState<_TorrentTabView> createState() => _TorrentTabViewState();
}

class _TorrentTabViewState extends ConsumerState<_TorrentTabView> {
  TorrentTask? _task;
  List<TorrentFileEntry> _files = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = ref.read(servicesProvider);
    try {
      final task = widget.tab.contentId != null
          ? await s.torrents.taskById(widget.tab.contentId!)
          : null;
      final resolved = task ?? await _byInfoHash(s);
      final files = resolved == null ? const <TorrentFileEntry>[] : await s.torrents.filesFor(resolved.id);
      if (!mounted) return;
      setState(() {
        _task = resolved;
        _files = files;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<TorrentTask?> _byInfoHash(AppServices s) async {
    final all = await s.torrents.listTasks();
    for (final t in all) {
      if (t.infoHashHex == widget.tab.location) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final task = _task;
    if (task == null) {
      return ErrorView(
        message: 'This torrent is no longer in the task list (it may have been removed).\n\n'
            'Info-hash: ${widget.tab.location}',
        onRetry: _load,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(task.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '${task.state.name} · ${Fmt.bytes(task.downloadedBytes)} of ${Fmt.bytes(task.totalBytes)} '
                '· ${Fmt.speed(task.downloadBps)} · ${task.connectedPeers} peer(s)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: task.totalBytes == 0 ? null : task.progress),
              if (task.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(task.errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _files.isEmpty
              ? const EmptyView(
                  icon: Icons.hourglass_empty,
                  title: 'No file list yet',
                  message: 'Metadata is still resolving, or the task has no files.',
                )
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, i) {
                    final f = _files[i];
                    final full = p.join(task.savePath, f.path);
                    final fraction = f.sizeBytes <= 0 ? 0.0 : (f.downloadedBytes / f.sizeBytes).clamp(0.0, 1.0);
                    return ListTile(
                      leading: Icon(_iconFor(f.path)),
                      title: Text(p.basename(f.path), maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${ContentRouter.labelFor(ContentRouter.kindOf(f.path))} · '
                          '${Fmt.bytes(f.sizeBytes)}'
                          '${fraction > 0 && fraction < 1 ? ' · ${Fmt.percent(fraction)}' : ''}'),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => ContentRouter.open(
                        context,
                        path: full,
                        title: p.basename(f.path),
                        contentId: '${task.id}:${f.fileIndex}',
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  static IconData _iconFor(String path) => switch (ContentRouter.kindOf(path)) {
        ContentKind.video => Icons.movie_outlined,
        ContentKind.audio => Icons.music_note_outlined,
        ContentKind.epub => Icons.menu_book_outlined,
        ContentKind.pdf => Icons.picture_as_pdf_outlined,
        ContentKind.comic => Icons.collections_bookmark_outlined,
        ContentKind.image => Icons.image_outlined,
        ContentKind.text => Icons.description_outlined,
        ContentKind.html => Icons.public,
        ContentKind.unknown => Icons.insert_drive_file_outlined,
      };
}

/// A discovered media resource that has not been opened in a player yet.
class _MediaTabView extends ConsumerWidget {
  final BrowserTab tab;
  const _MediaTabView({required this.tab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.read(tabManagerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tab.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SelectableText(tab.location, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: () => manager.openContent(
              type: BrowserTabType.player,
              location: tab.location,
              title: tab.title,
              contentId: tab.contentId,
            ),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Open in the player'),
          ),
        ],
      ),
    );
  }
}
