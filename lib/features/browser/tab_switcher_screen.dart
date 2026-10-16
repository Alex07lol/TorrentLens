import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/tabs/browser_tab.dart';
import '../../util/format.dart';
import 'tab_manager.dart';
import 'tab_strip.dart';

/// The tab overview: every open tab as a card, most useful information first.
///
/// This is where a phone browser puts "all tabs", because a strip alone cannot
/// show twenty of them. Tapping a card focuses it; the ✕ closes one tab.
class TabSwitcherScreen extends ConsumerWidget {
  const TabSwitcherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final set = ref.watch(tabManagerProvider);
    final manager = ref.read(tabManagerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text('${set.length} open tab${set.length == 1 ? '' : 's'}'),
        actions: [
          IconButton(
            tooltip: 'New tab',
            onPressed: () {
              manager.openHomeTab();
              context.pop();
            },
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Close all tabs',
            onPressed: set.length <= 1 ? null : () => _confirmCloseAll(context, ref),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: set.isEmpty
          ? const Center(child: Text('No tabs are open.'))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
              ),
              itemCount: set.tabs.length,
              itemBuilder: (context, i) {
                final tab = set.tabs[i];
                return _TabCard(
                  tab: tab,
                  index: i,
                  active: tab.id == set.activeId,
                  onOpen: () {
                    manager.activate(tab.id);
                    context.pop();
                  },
                  onClose: () => manager.close(tab.id),
                  onCloseOthers: () {
                    manager.closeOthers(tab.id);
                    context.pop();
                  },
                );
              },
            ),
    );
  }

  Future<void> _confirmCloseAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close all tabs?'),
        content: const Text(
          'This closes every open tab and leaves one blank tab.\n\n'
          'Downloads, files, reading positions and torrent tasks are not affected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Close all')),
        ],
      ),
    );
    if (ok == true) ref.read(tabManagerProvider.notifier).closeAll();
  }
}

class _TabCard extends StatelessWidget {
  final BrowserTab tab;
  final int index;
  final bool active;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final VoidCallback onCloseOthers;

  const _TabCard({
    required this.tab,
    required this.index,
    required this.active,
    required this.onOpen,
    required this.onClose,
    required this.onCloseOthers,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = _subtitle(tab);
    return Card(
      color: active ? scheme.secondaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onCloseOthers,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(tabTypeIcon(tab.type), size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tab.title.isEmpty ? tab.type.name : tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close tab',
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const Spacer(),
              if (tab.error != null)
                Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: scheme.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tab.error!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 4),
              Text(
                tab.lastVisitedAtMs == null
                    ? 'Tab ${index + 1}'
                    : 'Tab ${index + 1} · ${Fmt.relativeTime(DateTime.fromMillisecondsSinceEpoch(tab.lastVisitedAtMs!))}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle(BrowserTab tab) {
    if (tab.location.isEmpty) return 'Blank tab';
    if (tab.location.startsWith('file:')) {
      final uri = Uri.tryParse(tab.location);
      if (uri != null && uri.pathSegments.isNotEmpty) return uri.pathSegments.last;
    }
    return tab.location;
  }
}
