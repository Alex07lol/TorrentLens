import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../design_system/components.dart';
import '../../util/permissions.dart';

/// Settings: storage, bandwidth, background behaviour, security and diagnostics.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _downloadDir;
  String? _downloadLimit;
  String? _uploadLimit;
  int _taskCount = 0;
  int _libraryCount = 0;
  int _pendingSync = 0;
  bool _notificationsGranted = false;
  bool? _engineRunning;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = ref.read(servicesProvider);
    final dir = await s.settings.get('storage.downloadDir') ?? s.defaultDownloadDir;
    final dl = await s.settings.get('net.downloadLimitBps') ?? '0';
    final ul = await s.settings.get('net.uploadLimitBps') ?? '0';
    final tasks = await s.torrents.listTasks();
    final library = await s.library.list();
    final pending = await s.syncQueue.count();
    bool? running;
    try {
      running = await s.engine.isRunning();
    } catch (_) {
      running = null;
    }
    final notif = await AppPermissions.notificationsGranted();
    if (!mounted) return;
    setState(() {
      _downloadDir = dir;
      _downloadLimit = dl;
      _uploadLimit = ul;
      _taskCount = tasks.length;
      _libraryCount = library.length;
      _pendingSync = pending;
      _engineRunning = running;
      _notificationsGranted = notif;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          SectionCard(
            title: 'Appearance',
            child: Column(
              children: [
                SegmentedButton<ThemeMode>(
                  segments: [
                    for (final mode in ThemeMode.values)
                      ButtonSegment(
                        value: mode,
                        label: Text(mode.name[0].toUpperCase() + mode.name.substring(1)),
                      ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (selection) =>
                      ref.read(themeModeProvider.notifier).set(selection.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Storage',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_downloadDir ?? '—', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Text(
                  'Without a chosen folder, downloads go to this app\'s own storage, '
                  'which needs no permission. Choosing another folder uses Android\'s '
                  'folder picker (Storage Access Framework).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _chooseDownloadDir,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose download folder'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Bandwidth',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LimitField(
                  label: 'Download limit (KiB/s, 0 = unlimited)',
                  initial: _downloadLimit ?? '0',
                  onChanged: (v) => _downloadLimit = v,
                ),
                const SizedBox(height: 12),
                _LimitField(
                  label: 'Upload limit (KiB/s, 0 = unlimited)',
                  initial: _uploadLimit ?? '0',
                  onChanged: (v) => _uploadLimit = v,
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _applyLimits,
                  icon: const Icon(Icons.speed),
                  label: const Text('Apply limits'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Background & notifications',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active transfers run in a foreground service with a visible notification, '
                  'which Android requires for background work. Whether a transfer keeps running '
                  'depends on your device\'s battery settings; TorrentLens re-syncs its state on launch.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text('Notifications: ${_notificationsGranted ? 'granted' : 'not granted'}'),
                    ),
                    TextButton(
                      onPressed: _requestNotifications,
                      child: Text(_notificationsGranted ? 'Re-check' : 'Allow'),
                    ),
                  ],
                ),
                Text(AppPermissions.rationale['notifications']!,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Publishers & cloud',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GitHub is used to discover publisher releases. A publisher may also host '
                  'its own optional cloud backend; TorrentLens never requires one.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => context.push('/cloud'),
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('Cloud sync'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Diagnostics',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('Torrent engine', _engineRunning == null ? 'unavailable' : (_engineRunning! ? 'running' : 'stopped')),
                _kv('Torrent tasks', '$_taskCount'),
                _kv('Library entries', '$_libraryCount'),
                _kv('Pending sync writes', '$_pendingSync'),
                _kv('App version', '1.0.0'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Privacy',
            child: Text(
              'Ordinary BitTorrent connections expose your IP address to peers and trackers. '
              'TorrentLens makes no attempt to hide your network identity. Cloud sync is opt-in '
              'and only uploads the data types you enable.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(k)),
            Text(v, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );

  Future<void> _chooseDownloadDir() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    await ref.read(servicesProvider).settings.set('storage.downloadDir', path);
    await _load();
  }

  Future<void> _applyLimits() async {
    final s = ref.read(servicesProvider);
    final dl = (int.tryParse(_downloadLimit ?? '0') ?? 0) * 1024;
    final ul = (int.tryParse(_uploadLimit ?? '0') ?? 0) * 1024;
    await s.settings.set('net.downloadLimitBps', (dl ~/ 1024).toString());
    await s.settings.set('net.uploadLimitBps', (ul ~/ 1024).toString());
    try {
      await s.engine.setSessionLimits(downloadLimitBps: dl, uploadLimitBps: ul);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Session limits applied.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Limits saved; engine not running: $e')));
      }
    }
  }

  Future<void> _requestNotifications() async {
    final granted = await AppPermissions.requestNotifications();
    if (!mounted) return;
    if (!granted) {
      await AppPermissions.openSettings();
    }
    await _load();
  }
}

class _LimitField extends StatefulWidget {
  final String label;
  final String initial;
  final ValueChanged<String> onChanged;
  const _LimitField({required this.label, required this.initial, required this.onChanged});
  @override
  State<_LimitField> createState() => _LimitFieldState();
}

class _LimitFieldState extends State<_LimitField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: widget.label),
        onChanged: widget.onChanged,
      );
}
