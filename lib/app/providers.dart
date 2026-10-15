import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services.dart';

/// Overridden in `main()` with the real, asynchronously-built container.
final servicesProvider = Provider<AppServices>(
  (ref) => throw UnimplementedError('servicesProvider must be overridden at startup'),
);

/// Theme mode, persisted in the settings table.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(servicesProvider).settings.set('ui.themeMode', mode.name);
  }

  Future<void> load() async {
    final raw = await ref.read(servicesProvider).settings.get('ui.themeMode');
    if (raw == null) return;
    state = ThemeMode.values.firstWhere((m) => m.name == raw, orElse: () => ThemeMode.system);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// A monotonically increasing counter used to force list screens to refresh
/// after a mutation (add torrent, subscribe, …) without global state plumbing.
class RefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state = state + 1;
}

final refreshProvider = NotifierProvider<RefreshNotifier, int>(RefreshNotifier.new);
