import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_system/theme.dart';
import '../features/browser/tab_manager.dart';
import '../navigation/router.dart';
import 'providers.dart';

class TorrentLensApp extends ConsumerStatefulWidget {
  const TorrentLensApp({super.key});
  @override
  ConsumerState<TorrentLensApp> createState() => _TorrentLensAppState();
}

class _TorrentLensAppState extends ConsumerState<TorrentLensApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Load the persisted theme choice and the persisted tab workspace after the
    // first frame, so a slow database read never delays the first paint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(themeModeProvider.notifier).load();
      ref.read(tabManagerProvider.notifier).restore();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Tab writes are debounced, so a process that is killed in the background
    // can lose the last few seconds. Flush them when the app stops being
    // visible — the same moment Android may freeze or kill it.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      ref.read(tabManagerProvider.notifier).persistNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'TorrentLens',
      debugShowCheckedModeBanner: false,
      theme: TorrentLensTheme.light(),
      darkTheme: TorrentLensTheme.dark(),
      themeMode: mode,
      routerConfig: appRouter,
    );
  }
}
