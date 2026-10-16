import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../design_system/components.dart';
import '../../domain/tabs/browser_address.dart';
import '../../domain/tabs/browser_tab.dart';
import '../../domain/tabs/tab_set.dart';
import '../../navigation/shell.dart';
import '../../util/system_share.dart';
import '../downloads/torrent_import_service.dart';
import 'address_bar.dart';
import 'tab_content_host.dart';
import 'tab_manager.dart';
import 'tab_strip.dart';

/// The tabbed workspace: the app's main destination.
///
/// Layout is deliberately thin — one strip row, an address bar only when the
/// active tab is a web page, then the content. Everything below the chrome is
/// whatever the active tab is (page, reader, player, torrent, dashboard), so no
/// screen has to know about tabs to be hosted in one.
class BrowserWorkspace extends ConsumerStatefulWidget {
  const BrowserWorkspace({super.key});

  @override
  ConsumerState<BrowserWorkspace> createState() => _BrowserWorkspaceState();
}

class _BrowserWorkspaceState extends ConsumerState<BrowserWorkspace> {
  /// Bumped to force one tab's content to be rebuilt from scratch (reload, or a
  /// tab that was evicted and is now live again).
  final Map<String, int> _generations = {};

  void _reload(String tabId) {
    setState(() => _generations[tabId] = (_generations[tabId] ?? 0) + 1);
  }

  @override
  Widget build(BuildContext context) {
    final set = ref.watch(tabManagerProvider);
    final manager = ref.read(tabManagerProvider.notifier);
    final active = set.active;
    final live = set.liveIds().toSet();
    final activeIndex = active == null ? 0 : set.indexOf(active.id);

    // The workspace hangs off an IndexedStack, so it is mounted even while the
    // user is on another destination. Back must only be intercepted while the
    // workspace is actually the visible destination; on Downloads, Explorer or
    // any other tab, back keeps its normal meaning.
    final onWorkspace = ref.watch(shellIndexProvider) == ShellTab.tabs;
    final canHandleBack = (active?.canGoBack ?? false) || set.length > 1;

    return PopScope(
      // Back stays inside the app while there is anywhere to go: the address
      // history of the active tab first, then the tab workspace itself.
      canPop: !(onWorkspace && canHandleBack),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !onWorkspace) return;
        if (active?.canGoBack ?? false) {
          manager.back();
        } else if (set.length > 1) {
          manager.closeActive();
        }
      },
      child: Column(
        children: [
          TabStrip(
            onNewTab: () => manager.openHomeTab(),
            onOverview: () => context.push('/tabs'),
          ),
          if (active != null && active.type == BrowserTabType.web)
            AddressBar(
              url: _addressFor(active),
              loading: active.loading,
              canGoBack: active.canGoBack,
              canGoForward: active.canGoForward,
              insecure: active.location.startsWith('http://'),
              onSubmit: (raw) => _submitAddress(context, raw),
              onBack: () => manager.back(),
              onForward: () => manager.forward(),
              onReload: () => _reload(active.id),
              onCopy: () => AddressBar.copy(context, active.location, 'Address copied'),
              onShare: () => _share(active),
              onOpenExternal: () => _openExternal(context, active),
            ),
          const Divider(height: 1),
          Expanded(
            child: set.tabs.isEmpty
                ? const EmptyView(
                    icon: Icons.tab_unselected_outlined,
                    title: 'No tabs',
                    message: 'Open a tab to browse, read or play something.',
                  )
                : IndexedStack(
                    index: activeIndex,
                    children: [
                      for (final tab in set.tabs)
                        live.contains(tab.id)
                            ? TabContentHost(
                                key: ValueKey('${tab.id}-${_generations[tab.id] ?? 0}'),
                                tab: tab,
                                onReload: () => _reload(tab.id),
                              )
                            : _EvictedTab(tab: tab, onReload: () => _reload(tab.id)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// What the address bar shows: the live page URL, or the last known one.
  String _addressFor(BrowserTab tab) =>
      tab.location.startsWith('file:') ? tab.title : tab.location;

  Future<void> _submitAddress(BuildContext context, String raw) async {
    final manager = ref.read(tabManagerProvider.notifier);
    final input = raw.trim();
    if (input.isEmpty) return;

    final parsed = BrowserAddress.parse(input);
    if (parsed.isMagnet) {
      final result = await TorrentImportService(ref.read(servicesProvider)).addMagnet(input);
      if (!context.mounted) return;
      if (!result.ok) {
        _say(context, result.error ?? 'That magnet link could not be added.');
        return;
      }
      final hash = result.infoHash;
      if (hash != null) {
        manager.openTorrent(
          infoHash: hash,
          title: 'Torrent ${hash.substring(0, 8)}',
          taskId: result.taskId,
        );
      }
      _say(context, 'Magnet added. It is in Downloads while metadata resolves.');
      return;
    }

    final url = parsed.url;
    if (url == null) {
      _say(context, parsed.rejection ?? 'That address could not be understood.');
      return;
    }
    manager.navigate(
      location: url.toString(),
      title: url.host.isEmpty ? url.toString() : url.host,
      type: BrowserTabType.web,
    );
  }

  Future<void> _share(BrowserTab tab) async {
    final ok = await SystemShare.text(tab.location, subject: tab.title);
    if (!ok && mounted) {
      _say(context, 'No app on this device accepted the share.');
    }
  }

  Future<void> _openExternal(BuildContext context, BrowserTab tab) async {
    final uri = Uri.tryParse(tab.location);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      _say(context, 'Only http(s) pages can be opened in another browser.');
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) _say(context, 'No browser accepted that address: $e');
    }
  }

  void _say(BuildContext context, String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// A tab whose live resource was released to stay inside the memory budget.
class _EvictedTab extends StatelessWidget {
  final BrowserTab tab;
  final VoidCallback onReload;

  const _EvictedTab({required this.tab, required this.onReload});

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      icon: tabTypeIcon(tab.type),
      title: tab.title.isEmpty ? tab.type.name : tab.title,
      message: 'This tab was set aside to keep memory free '
          '(${TabSet.defaultMaxLiveTabs} tabs stay loaded at once).\n'
          'Its content was not lost: opening it again reloads it here.',
      action: FilledButton.tonalIcon(
        onPressed: onReload,
        icon: const Icon(Icons.refresh),
        label: const Text('Reload this tab'),
      ),
    );
  }
}
