import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design_system/components.dart';
import '../../util/format.dart';
import '../library/content_router.dart';

/// File explorer over the real filesystem. It browses the app's download
/// directory (and any directory the user chooses) without needing broad storage
/// permission, because it only reads paths it already has access to.
class ExplorerScreen extends ConsumerStatefulWidget {
  const ExplorerScreen({super.key});
  @override
  ConsumerState<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends ConsumerState<ExplorerScreen> {
  late Directory _current;
  List<FileSystemEntity> _entries = const [];
  bool _loading = true;
  String? _error;
  final List<Directory> _history = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final s = ref.read(servicesProvider);
    final root = await s.settings.get('storage.downloadDir') ?? s.defaultDownloadDir;
    _current = Directory(root);
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!_current.existsSync()) _current.createSync(recursive: true);
      final entries = _current.listSync()..sort((a, b) {
          final ad = a is Directory, bd = b is Directory;
          if (ad != bd) return ad ? -1 : 1;
          return a.path.toLowerCase().compareTo(b.path.toLowerCase());
        });
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _enter(Directory dir) {
    _history.add(_current);
    _current = dir;
    _load();
  }

  void _up() {
    if (_history.isEmpty) return;
    _current = _history.removeLast();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Explore'),
        leading: _history.isEmpty
            ? null
            : IconButton(onPressed: _up, icon: const Icon(Icons.arrow_back)),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_current.path,
                      style: Theme.of(context).textTheme.labelMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : _entries.isEmpty
                        ? const EmptyView(
                            icon: Icons.folder_open,
                            title: 'This folder is empty',
                            message: 'Downloaded torrent contents appear here as they complete.',
                          )
                        : ListView.separated(
                            itemCount: _entries.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final entity = _entries[i];
                              final name = entity.path.split('/').last;
                              if (entity is Directory) {
                                return ListTile(
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: scheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.folder,
                                        color: scheme.onSecondaryContainer),
                                  ),
                                  title: Text(name),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _enter(entity),
                                );
                              }
                              final size = entity.statSync().size;
                              return ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(_iconFor(name), color: scheme.onSurfaceVariant),
                                ),
                                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${ContentRouter.labelFor(ContentRouter.kindOf(name))} · ${Fmt.bytes(size)}'),
                                trailing: const Icon(Icons.open_in_new),
                                onTap: () => ContentRouter.open(context, path: entity.path, title: name),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String name) => switch (ContentRouter.kindOf(name)) {
        ContentKind.epub => Icons.menu_book_outlined,
        ContentKind.pdf => Icons.picture_as_pdf_outlined,
        ContentKind.comic => Icons.auto_stories_outlined,
        ContentKind.text => Icons.description_outlined,
        ContentKind.image => Icons.image_outlined,
        ContentKind.video => Icons.movie_outlined,
        ContentKind.audio => Icons.music_note_outlined,
        ContentKind.html => Icons.public,
        ContentKind.unknown => Icons.insert_drive_file_outlined,
      };
}
