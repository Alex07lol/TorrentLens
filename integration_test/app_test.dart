// Device integration tests. These require a real Android device or emulator:
//
//   flutter test integration_test/app_test.dart -d <device-id>
//
// They are NOT run by `flutter test` (which only runs the unit suite), because
// they exercise the actual Android platform channel and native libtorrent4j
// engine. Nothing here is mocked.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:torrentlens/app/app.dart';
import 'package:torrentlens/app/providers.dart';
import 'package:torrentlens/app/services.dart';
import 'package:torrentlens/integrations/torrent/torrent_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots into the navigation shell', (tester) async {
    final services = await AppServices.open();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [servicesProvider.overrideWithValue(services)],
        child: const TorrentLensApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    // The shell must render at least one navigation destination.
    expect(find.byType(NavigationBar), findsWidgets);

    await services.db.close();
  });

  testWidgets('native torrent engine is reachable over the platform channel',
      (tester) async {
    final engine = MethodChannelTorrentEngine();

    // Proves the Kotlin plugin answers, not that a download works.
    expect(await engine.isRunning(), isA<bool>());

    await engine.start(const EngineOptions());
    expect(await engine.isRunning(), isTrue);

    // A session that started must report an (empty) status list.
    expect(await engine.allStatus(), isEmpty);

    await engine.stop();
    expect(await engine.isRunning(), isFalse);
  });
}
