import 'package:go_router/go_router.dart';

import '../features/cloud_sync/cloud_sync_screen.dart';
import '../features/player/player_screen.dart';
import '../features/reader/comic_reader_screen.dart';
import '../features/reader/epub_reader_screen.dart';
import '../features/reader/pdf_reader_screen.dart';
import '../features/reader/text_reader_screen.dart';
import '../features/web_sandbox/web_sandbox_screen.dart';
import 'route_args.dart';
import 'shell.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(path: '/', redirect: (_, _) => '/home'),
    GoRoute(path: '/home', builder: (_, _) => const HomeShell()),
    GoRoute(
      path: '/player',
      builder: (_, state) => PlayerScreen(args: state.extra as PlayerArgs),
    ),
    GoRoute(
      path: '/reader/epub',
      builder: (_, state) => EpubReaderScreen(args: state.extra as ReaderArgs),
    ),
    GoRoute(
      path: '/reader/pdf',
      builder: (_, state) => PdfReaderScreen(args: state.extra as ReaderArgs),
    ),
    GoRoute(
      path: '/reader/comic',
      builder: (_, state) => ComicReaderScreen(args: state.extra as ReaderArgs),
    ),
    GoRoute(
      path: '/reader/text',
      builder: (_, state) => TextReaderScreen(args: state.extra as ReaderArgs),
    ),
    GoRoute(
      path: '/web',
      builder: (_, state) => WebSandboxScreen(args: state.extra as WebSandboxArgs),
    ),
    GoRoute(path: '/cloud', builder: (_, _) => const CloudSyncScreen()),
  ],
);
