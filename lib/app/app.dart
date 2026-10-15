import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_system/theme.dart';
import '../navigation/router.dart';
import 'providers.dart';

class TorrentLensApp extends ConsumerStatefulWidget {
  const TorrentLensApp({super.key});
  @override
  ConsumerState<TorrentLensApp> createState() => _TorrentLensAppState();
}

class _TorrentLensAppState extends ConsumerState<TorrentLensApp> {
  @override
  void initState() {
    super.initState();
    // Load the persisted theme choice after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(themeModeProvider.notifier).load();
    });
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
