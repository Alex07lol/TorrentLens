import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/browser/browser_workspace.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/explorer/explorer_screen.dart';
import '../features/library/library_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/subscriptions/subscriptions_screen.dart';

/// The app's six top-level destinations. The first one is the tabbed browser
/// workspace; the old dashboard now lives inside its new-tab page, so the
/// bottom bar did not grow.
enum ShellTab { tabs, downloads, explorer, library, subscriptions, settings }

class ShellIndexNotifier extends Notifier<ShellTab> {
  @override
  ShellTab build() => ShellTab.tabs;

  void set(ShellTab tab) => state = tab;
}

final shellIndexProvider = NotifierProvider<ShellIndexNotifier, ShellTab>(ShellIndexNotifier.new);

/// Mobile-first navigation: a bottom navigation bar over an IndexedStack so
/// each destination keeps its scroll position and state.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static const _destinations = <NavigationDestination>[
    NavigationDestination(icon: Icon(Icons.tab_unselected_outlined), selectedIcon: Icon(Icons.tab_outlined), label: 'Tabs'),
    NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Downloads'),
    NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Explore'),
    NavigationDestination(icon: Icon(Icons.collections_bookmark_outlined), selectedIcon: Icon(Icons.collections_bookmark), label: 'Library'),
    NavigationDestination(icon: Icon(Icons.new_releases_outlined), selectedIcon: Icon(Icons.new_releases), label: 'Subs'),
    NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(shellIndexProvider);
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: index.index,
          children: const [
            BrowserWorkspace(),
            DownloadsScreen(),
            ExplorerScreen(),
            LibraryScreen(),
            SubscriptionsScreen(),
            SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index.index,
        destinations: _destinations,
        onDestinationSelected: (i) => ref.read(shellIndexProvider.notifier).set(ShellTab.values[i]),
      ),
    );
  }
}
