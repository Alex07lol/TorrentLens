import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'app/services.dart';
import 'features/subscriptions/update_worker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The container is built before the first frame so no screen has to deal
  // with a half-initialised database.
  final services = await AppServices.open();

  // Deferred publisher checks are scheduled by WorkManager. The app used to
  // declare the dependency without ever registering a task, so nothing was
  // scheduled; this is that registration. It is best-effort: a device that
  // refuses background work still starts, and manual refresh keeps working.
  unawaited(UpdateCheckScheduler.ensureScheduled());

  runApp(
    ProviderScope(
      overrides: [servicesProvider.overrideWithValue(services)],
      child: const TorrentLensApp(),
    ),
  );
}
