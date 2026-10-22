import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design_system/components.dart';
import '../../design_system/theme.dart';
import '../../domain/models/subscription.dart';
import '../../domain/models/library_entry.dart';
import '../../domain/models/torrent_task.dart';
import '../../integrations/torrent/torrent_engine.dart';
import '../../util/format.dart';

/// Dashboard: engine session state, active transfers, recent content and
/// subscription update alerts. Every number shown comes from the real engine or
/// the database — none of it is simulated.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _timer;
  bool _engineRunning = false;
  List<EngineStatus> _statuses = const [];
  List<TorrentTask> _tasks = const [];
  List<LibraryEntry> _recent = const [];
  List<Subscription> _updates = const [];
  String? _engineError;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final s = ref.read(servicesProvider);
    try {
      final running = await s.engine.isRunning();
      final statuses = running ? await s.engine.allStatus() : const <EngineStatus>[];
      final tasks = await s.torrents.listTasks();
      final library = await s.library.list();
      final subs = await s.subscriptions.list();
      if (!mounted) return;
      setState(() {
        _engineRunning = running;
        _statuses = statuses;
        _tasks = tasks;
        _recent = library.where((e) => e.lastOpenedAtMs != null).take(5).toList();
        _updates = subs
            .where((s) => s.latestVersion != null && s.latestVersion != s.installedVersion)
            .toList();
        _engineError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _engineError = '$e');
    }
  }

  int get _activeCount =>
      _statuses.where((s) => const {'downloading', 'resolvingMetadata', 'checking'}.contains(s.state)).length;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(servicesProvider);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Text('TorrentLens', style: Theme.of(context).textTheme.headlineSmall),
          Text(
            'Local-first torrent client, reader and publisher subscriptions.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (_engineError != null) ...[
            SectionCard(
              title: 'Native engine unavailable',
              child: Text(
                'The libtorrent engine could not be reached on this platform:\n$_engineError\n\n'
                'The UI, library, readers and subscriptions still work; only transfers are disabled here.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),
          ],
          SectionCard(
            title: 'Session',
            trailing: StatusPill(
              label: _engineRunning ? 'Engine running' : 'Engine stopped',
              color: _engineRunning ? Colors.green : Colors.grey,
              icon: _engineRunning ? Icons.play_circle_outline : Icons.pause_circle_outline,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_engineRunning && _statuses.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: StatReadout(
                            value: Fmt.speed(
                                _statuses.fold(0, (sum, st) => sum + st.downloadBps)),
                            label: 'download',
                            icon: Icons.arrow_downward,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        Expanded(
                          child: StatReadout(
                            value: Fmt.speed(
                                _statuses.fold(0, (sum, st) => sum + st.uploadBps)),
                            label: 'upload',
                            icon: Icons.arrow_upward,
                          ),
                        ),
                        Expanded(
                          child: StatReadout(
                            value: '${_statuses.fold(0, (sum, st) => sum + st.numPeers)}',
                            label: 'peers',
                            icon: Icons.people_outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                Text('${_tasks.length} task(s), $_activeCount active',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text('Download dir: ${s.defaultDownloadDir}',
                    style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _engineRunning ? _stopEngine : _startEngine,
                      icon: Icon(_engineRunning ? Icons.stop : Icons.play_arrow),
                      label: Text(_engineRunning ? 'Stop engine' : 'Start engine'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Active transfers',
            child: _statuses.isEmpty
                ? const Text('No transfers are running.', style: TextStyle(fontSize: 13))
                : Column(
                    children: [
                      for (final st in _statuses.take(4))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(st.infoHash.substring(0, 12),
                                        style: const TextStyle(
                                            fontFamily: 'monospace', fontSize: 13)),
                                  ),
                                  Text(
                                      '↓${Fmt.speed(st.downloadBps)}  ↑${Fmt.speed(st.uploadBps)}',
                                      style: Theme.of(context).textTheme.labelMedium),
                                ],
                              ),
                              const SizedBox(height: 6),
                              StateProgress(
                                value: st.totalBytes == 0 ? null : st.progress,
                                color: TorrentLensTheme.stateColor(
                                    st.state, Theme.of(context).brightness),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Publisher updates',
            child: _updates.isEmpty
                ? const Text('No updates detected for your subscriptions yet.', style: TextStyle(fontSize: 13))
                : Column(
                    children: [
                      for (final sub in _updates)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.new_releases_outlined),
                          title: Text(sub.title),
                          subtitle: Text('${sub.installedVersion ?? 'not installed'} → ${sub.latestVersion}'),
                          trailing: StatusPill(
                            label: sub.trustStatus,
                            color: sub.trustStatus == 'verified' ? Colors.green : Colors.orange,
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Recently opened',
            child: _recent.isEmpty
                ? const Text('Nothing opened yet.', style: TextStyle(fontSize: 13))
                : Column(
                    children: [
                      for (final e in _recent)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${e.kind} · opened ${Fmt.relativeTime(DateTime.fromMillisecondsSinceEpoch(e.lastOpenedAtMs!))}'),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _startEngine() async {
    final s = ref.read(servicesProvider);
    await s.engine.start(const EngineOptions());
    await _refresh();
  }

  Future<void> _stopEngine() async {
    await ref.read(servicesProvider).engine.stop();
    await _refresh();
  }
}
