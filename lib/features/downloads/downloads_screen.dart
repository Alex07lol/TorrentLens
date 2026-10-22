import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../design_system/components.dart';
import '../../design_system/theme.dart';
import '../../domain/models/torrent_task.dart';
import '../../domain/torrent/streaming.dart';
import '../../integrations/torrent/torrent_engine.dart';
import '../../navigation/route_args.dart';
import '../../util/format.dart';
import '../library/content_router.dart';
import 'torrent_import_service.dart';

/// The Downloads destination: real task list, real speeds, real controls.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});
  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  Timer? _timer;
  List<TorrentTask> _tasks = const [];
  Map<String, EngineStatus> _statuses = const {};
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
      final tasks = await s.torrents.listTasks();
      Map<String, EngineStatus> statuses = const {};
      final running = await s.engine.isRunning();
      if (running) {
        statuses = {for (final st in await s.engine.allStatus()) st.infoHash: st};
      }
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _statuses = statuses;
        _engineError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _engineError = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          IconButton(
            tooltip: 'Re-check all tasks',
            onPressed: _recheckAll,
            icon: const Icon(Icons.fact_check_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add),
        label: const Text('Add torrent'),
      ),
      body: _engineError != null
          ? ErrorView(message: _engineError!, onRetry: _refresh)
          : _tasks.isEmpty
              ? EmptyView(
                  icon: Icons.download_outlined,
                  title: 'No downloads yet',
                  message: 'Paste a magnet link, add a .torrent file, or import a torrent URL.',
                  action: FilledButton.tonalIcon(
                    onPressed: _openAddSheet,
                    icon: const Icon(Icons.add),
                    label: const Text('Add torrent'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: _tasks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _TaskCard(
                    task: _tasks[i],
                    status: _statuses[_tasks[i].infoHashHex],
                    onPause: () => _control(() => ref.read(servicesProvider).engine.pause(_tasks[i].infoHashHex!)),
                    onResume: () => _control(() => ref.read(servicesProvider).engine.resume(_tasks[i].infoHashHex!)),
                    onRemove: () => _remove(_tasks[i]),
                    onSelectFiles: () => _openFileSheet(_tasks[i]),
                    onRecheck: () =>
                        _control(() => ref.read(servicesProvider).engine.recheck(_tasks[i].infoHashHex!)),
                    onStream: _tasks[i].infoHashHex == null
                        ? null
                        : () => _openStreamPicker(_tasks[i]),
                  ),
                ),
    );
  }

  Future<void> _control(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _snack('$e');
    }
    await _refresh();
  }

  Future<void> _recheckAll() async {
    for (final t in _tasks.where((t) => t.infoHashHex != null)) {
      try {
        await ref.read(servicesProvider).engine.recheck(t.infoHashHex!);
      } catch (_) {}
    }
    await _refresh();
  }

  Future<void> _remove(TorrentTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove transfer?'),
        content: Text('Removes "${task.name}" from the list. '
            'Downloaded files in ${task.savePath} are left on disk for you to manage.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (task.infoHashHex != null) {
        await ref.read(servicesProvider).engine.remove(task.infoHashHex!);
      }
    } catch (_) {}
    await ref.read(servicesProvider).torrents.deleteTask(task.id);
    await _refresh();
  }

  Future<void> _openAddSheet() async {
    final result = await showModalBottomSheet<ImportResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddTorrentSheet(),
    );
    if (result == null) return;
    await _refresh();
    if (!mounted) return;
    if (!result.ok) {
      _snack(result.error ?? 'Could not add that torrent.');
      return;
    }
    if (result.metadata != null && result.metadata!.files.isNotEmpty) {
      final task = _tasks.firstWhere((t) => t.id == result.taskId, orElse: () => _tasks.first);
      await _openFileSheet(task);
    } else {
      _snack('Torrent added. Metadata is still being resolved from peers.');
    }
  }

  /// Lists the media files a task already has a file list for, and opens the
  /// player in play-while-downloading mode for the chosen one.
  Future<void> _openStreamPicker(TorrentTask task) async {
    final s = ref.read(servicesProvider);
    final files = await s.torrents.filesFor(task.id);
    if (!mounted) return;
    if (files.isEmpty) {
      _snack('File list is not available yet — streaming needs metadata from peers.');
      return;
    }
    final playable = [
      for (final f in files)
        if (const {ContentKind.video, ContentKind.audio}.contains(ContentRouter.kindOf(f.path))) f,
    ];
    if (playable.isEmpty) {
      _snack('This torrent has no audio or video file to play while downloading.');
      return;
    }
    final chosen = await showModalBottomSheet<TorrentFileEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StreamPickerSheet(files: playable, taskName: task.name),
    );
    if (chosen == null || !mounted) return;
    final localPath = p.join(task.savePath, chosen.path);
    final target = StreamingTarget(
      infoHash: task.infoHashHex!,
      relativePath: chosen.path,
      localPath: localPath,
      fileLengthBytes: chosen.sizeBytes,
      title: chosen.path.split('/').last,
    );
    final kind = ContentRouter.kindOf(chosen.path);
    final kindLabel = ContentRouter.labelFor(kind);
    _snack('$kindLabel: playback starts once the pieces ahead of the playhead are ready.');
    context.push('/player', extra: PlayerArgs(
      source: localPath,
      title: chosen.path.split('/').last,
      isLocalFile: true,
      contentId: '${task.infoHashHex}:${chosen.path}',
      stream: target,
    ));
  }

  Future<void> _openFileSheet(TorrentTask task) async {
    final s = ref.read(servicesProvider);
    final files = await s.torrents.filesFor(task.id);
    if (files.isEmpty) {
      _snack('File list is not available yet — metadata is still resolving.');
      return;
    }
    if (!mounted) return;
    final selection = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FileSelectionSheet(files: files),
    );
    if (selection == null) return;
    final paths = {
      for (final f in files)
        if (selection.contains(f.fileIndex)) f.path,
    };
    try {
      await s.engine.setFileSelection(task.infoHashHex!, paths);
      for (final f in files) {
        await s.torrents.setFileSelected(task.id, f.fileIndex, paths.contains(f.path));
      }
      _snack('${paths.length} file(s) selected for download.');
    } catch (e) {
      _snack('$e');
    }
    await _refresh();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TaskCard extends StatelessWidget {
  final TorrentTask task;
  final EngineStatus? status;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRemove;
  final VoidCallback onSelectFiles;
  final VoidCallback onRecheck;

  /// Null when the task has no info-hash yet, so nothing can be prioritised.
  final VoidCallback? onStream;

  const _TaskCard({
    required this.task,
    required this.status,
    required this.onPause,
    required this.onResume,
    required this.onRemove,
    required this.onSelectFiles,
    required this.onRecheck,
    this.onStream,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final live = status;
    final fraction = live?.progress ?? task.progress;
    final downloaded = live?.downloadedBytes ?? task.downloadedBytes;
    final total = (live?.totalBytes ?? task.totalBytes);
    final downloadBps = live?.downloadBps ?? task.downloadBps;
    final uploadBps = live?.uploadBps ?? task.uploadBps;
    final peers = live?.numPeers ?? task.connectedPeers;
    final seeds = live?.numSeeds ?? 0;
    final stateLabel = live?.state ?? task.state.name;
    final error = live?.errorMessage ?? task.errorMessage;
    final active = const {'downloading', 'resolvingMetadata', 'checking', 'seeding'}.contains(stateLabel);
    final stateColor = TorrentLensTheme.stateColor(stateLabel, Theme.of(context).brightness);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(task.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(width: 8),
                StatusPill(label: stateLabel, color: stateColor),
              ],
            ),
            const SizedBox(height: 14),
            StateProgress(value: total == 0 ? null : fraction, color: stateColor),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatReadout(
                    value: Fmt.percent(fraction),
                    label: total == 0
                        ? 'Waiting for metadata'
                        : '${Fmt.bytes(downloaded)} of ${Fmt.bytes(total)}',
                  ),
                ),
                Expanded(
                  child: StatReadout(
                    value: '↓${Fmt.speed(downloadBps)}',
                    label: '↑${Fmt.speed(uploadBps)}',
                    color: downloadBps > 0 ? stateColor : null,
                    icon: Icons.downloading,
                  ),
                ),
                if (active && total > 0)
                  Expanded(
                    child: StatReadout(
                      value: Fmt.eta(total, downloaded, downloadBps),
                      label: 'remaining',
                      icon: Icons.hourglass_bottom,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.people_outline, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('$peers peers · $seeds seeds',
                    style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(width: 12),
                Icon(Icons.tag, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(task.infoHashHex?.substring(0, 12) ?? '—',
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            if (error != null && error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error,
                    style: TextStyle(color: scheme.error, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                    tooltip: 'Select files', onPressed: onSelectFiles, icon: const Icon(Icons.checklist)),
                IconButton(
                  tooltip: 'Play while downloading',
                  onPressed: onStream,
                  icon: const Icon(Icons.play_circle_outline),
                ),
                IconButton.filledTonal(
                  tooltip: active ? 'Pause' : 'Resume',
                  onPressed: active ? onPause : onResume,
                  icon: Icon(active ? Icons.pause : Icons.play_arrow, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(tooltip: 'Re-check data', onPressed: onRecheck, icon: const Icon(Icons.fact_check_outlined)),
                IconButton(tooltip: 'Remove', onPressed: onRemove, icon: const Icon(Icons.delete_outline)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTorrentSheet extends ConsumerStatefulWidget {
  const _AddTorrentSheet();
  @override
  ConsumerState<_AddTorrentSheet> createState() => _AddTorrentSheetState();
}

class _AddTorrentSheetState extends ConsumerState<_AddTorrentSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a torrent', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Magnet link, .torrent URL or info-hash',
              hintText: 'magnet:?xt=urn:btih:…',
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pickFile,
                  icon: const Icon(Icons.insert_drive_file_outlined),
                  label: const Text('.torrent file'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _submitText,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_link),
                  label: const Text('Add'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submitText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Enter a magnet link or a .torrent URL.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = TorrentImportService(ref.read(servicesProvider));
    final result = text.toLowerCase().startsWith('magnet:')
        ? await service.addMagnet(text)
        : await service.addTorrentUrl(text);
    if (!mounted) return;
    if (result.ok) {
      Navigator.pop(context, result);
    } else {
      setState(() {
        _busy = false;
        _error = result.error;
      });
    }
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['torrent'],
    );
    if (picked.isEmpty) return;
    final file = picked.single;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await TorrentImportService(ref.read(servicesProvider))
        .addTorrentBytes(bytes, name: file.name);
    if (!mounted) return;
    if (result.ok) {
      Navigator.pop(context, result);
    } else {
      setState(() {
        _busy = false;
        _error = result.error;
      });
    }
  }
}

/// Picks a media file to play from a torrent that is still downloading.
class _StreamPickerSheet extends StatefulWidget {
  final List<TorrentFileEntry> files;
  final String taskName;
  const _StreamPickerSheet({required this.files, required this.taskName});
  @override
  State<_StreamPickerSheet> createState() => _StreamPickerSheetState();
}

class _StreamPickerSheetState extends State<_StreamPickerSheet> {
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Play while downloading', style: Theme.of(context).textTheme.titleMedium),
            Text(
              'From ${widget.taskName}. The engine prioritises the pieces ahead of the '
              'playhead; playback starts once enough of the file is on disk, so the first '
              'seconds may buffer, and seeking may buffer again.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: widget.files.length,
                itemBuilder: (context, i) {
                  final f = widget.files[i];
                  final fraction = f.sizeBytes == 0 ? null : f.downloadedBytes / f.sizeBytes;
                  return ListTile(
                    leading: Icon(ContentRouter.kindOf(f.path) == ContentKind.audio
                        ? Icons.audiotrack
                        : Icons.movie_outlined),
                    title: Text(f.path, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${Fmt.bytes(f.sizeBytes)}'
                      '${f.selected ? '' : ' · not selected for download'}'
                      '${fraction == null ? '' : ' · ${Fmt.percent(fraction)} on disk'}',
                    ),
                    trailing: const Icon(Icons.play_arrow),
                    onTap: () => Navigator.pop(context, f),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileSelectionSheet extends StatefulWidget {
  final List<TorrentFileEntry> files;
  const _FileSelectionSheet({required this.files});
  @override
  State<_FileSelectionSheet> createState() => _FileSelectionSheetState();
}

class _FileSelectionSheetState extends State<_FileSelectionSheet> {
  late final Set<int> _selected = {
    for (final f in widget.files) if (f.selected) f.fileIndex,
  };

  @override
  Widget build(BuildContext context) {
    final total = widget.files.fold<int>(0, (a, f) => a + f.sizeBytes);
    final selectedBytes = widget.files
        .where((f) => _selected.contains(f.fileIndex))
        .fold<int>(0, (a, f) => a + f.sizeBytes);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Select files', style: Theme.of(context).textTheme.titleMedium),
            Text('${_selected.length} of ${widget.files.length} · '
                '${Fmt.bytes(selectedBytes)} of ${Fmt.bytes(total)}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: widget.files.length,
                itemBuilder: (context, i) {
                  final f = widget.files[i];
                  return CheckboxListTile(
                    dense: true,
                    value: _selected.contains(f.fileIndex),
                    title: Text(f.path, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(Fmt.bytes(f.sizeBytes)),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(f.fileIndex);
                      } else {
                        _selected.remove(f.fileIndex);
                      }
                    }),
                  );
                },
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, _selected),
              child: const Text('Apply selection'),
            ),
          ],
        ),
      ),
    );
  }
}
