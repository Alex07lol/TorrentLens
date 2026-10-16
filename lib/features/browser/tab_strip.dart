import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/tabs/browser_tab.dart';
import 'tab_manager.dart';

/// The active-tab indicator: a single compact row of chips, horizontal-scroll,
/// plus "new tab" and "all tabs".
///
/// On a phone the strip is a *selector*, not a desktop tab bar: it never wraps,
/// never pushes the content down more than one row, and long titles ellipsize.
/// The full overview lives in [TabSwitcherScreen].
class TabStrip extends ConsumerWidget {
  final VoidCallback onNewTab;
  final VoidCallback onOverview;
  final double height;

  const TabStrip({
    super.key,
    required this.onNewTab,
    required this.onOverview,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(tabManagerProvider).tabs;
    final manager = ref.read(tabManagerProvider.notifier);
    final activeId = ref.watch(tabManagerProvider).activeId;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final tab = tabs[i];
                final isActive = tab.id == activeId;
                return _TabChip(
                  tab: tab,
                  active: isActive,
                  labelStyle: Theme.of(context).textTheme.bodySmall,
                  background: isActive ? scheme.secondaryContainer : scheme.surfaceContainerHighest,
                  foreground: isActive ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                  onTap: () => manager.activate(tab.id),
                  onClose: () => manager.close(tab.id),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'New tab',
            onPressed: onNewTab,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'All tabs (${tabs.length})',
            onPressed: onOverview,
            icon: Badge(
              isLabelVisible: tabs.length > 1,
              label: Text('${tabs.length}'),
              child: const Icon(Icons.tab_unselected_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final BrowserTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final Color background;
  final Color foreground;
  final TextStyle? labelStyle;

  const _TabChip({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
    required this.background,
    required this.foreground,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: active ? 168 : 140,
          child: Padding(
            padding: const EdgeInsets.only(left: 10, right: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: tab.loading
                      ? const Padding(
                          padding: EdgeInsets.all(3),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : tab.error != null
                          ? Icon(Icons.error_outline, size: 16, color: Theme.of(context).colorScheme.error)
                          : Icon(tabTypeIcon(tab.type), size: 16, color: foreground),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tab.title.isEmpty ? _fallbackLabel(tab) : tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (labelStyle ?? const TextStyle(fontSize: 12)).copyWith(
                      color: foreground,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Close tab',
                  onPressed: onClose,
                  icon: Icon(Icons.close, size: 16, color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fallbackLabel(BrowserTab tab) => switch (tab.type) {
        BrowserTabType.home => 'New tab',
        BrowserTabType.web => tab.location,
        _ => tab.type.name,
      };
}

/// One icon per tab type, shared by the strip, the overview and the empty state.
IconData tabTypeIcon(BrowserTabType type) => switch (type) {
      BrowserTabType.home => Icons.add_circle_outline,
      BrowserTabType.web => Icons.public,
      BrowserTabType.torrent => Icons.download_outlined,
      BrowserTabType.explorer => Icons.folder_outlined,
      BrowserTabType.player => Icons.play_circle_outline,
      BrowserTabType.epub => Icons.menu_book_outlined,
      BrowserTabType.pdf => Icons.picture_as_pdf_outlined,
      BrowserTabType.comic => Icons.collections_bookmark_outlined,
      BrowserTabType.text => Icons.description_outlined,
      BrowserTabType.media => Icons.travel_explore,
      BrowserTabType.subscription => Icons.new_releases_outlined,
      BrowserTabType.cloud => Icons.cloud_outlined,
    };
