import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design_system/components.dart';
import '../../domain/models/library_entry.dart';
import '../../util/format.dart';
import 'content_router.dart';

/// The Library: everything the user can open, filterable and searchable.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  List<LibraryEntry> _entries = const [];
  String? _kindFilter;
  bool _favoritesOnly = false;
  String _search = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await ref.read(servicesProvider).library.list(
            kind: _kindFilter,
            search: _search,
            favoritesOnly: _favoritesOnly,
          );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            tooltip: 'Import a file into the library',
            onPressed: _importFile,
            icon: const Icon(Icons.library_add_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search titles',
              ),
              onChanged: (v) {
                _search = v;
                _load();
              },
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Favorites'),
                  selected: _favoritesOnly,
                  onSelected: (v) {
                    _favoritesOnly = v;
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                for (final kind in const ['epub', 'pdf', 'comicArchive', 'text', 'video', 'audio'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(kind),
                      selected: _kindFilter == kind,
                      onSelected: (v) {
                        _kindFilter = v ? kind : null;
                        _load();
                      },
                    ),
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
                            icon: Icons.collections_bookmark_outlined,
                            title: 'Your library is empty',
                            message: 'Files you download or import appear here, ready to open.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                            itemCount: _entries.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, i) => _LibraryTile(
                              entry: _entries[i],
                              onOpen: () => _open(_entries[i]),
                              onToggleFavorite: () => _toggleFavorite(_entries[i]),
                              onDelete: () => _delete(_entries[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(LibraryEntry entry) async {
    await ref.read(servicesProvider).library.touchOpened(entry.id, DateTime.now().millisecondsSinceEpoch);
    if (!mounted) return;
    ContentRouter.open(context, path: entry.path, title: entry.title, contentId: entry.id);
    _load();
  }

  Future<void> _toggleFavorite(LibraryEntry entry) async {
    await ref
        .read(servicesProvider)
        .library
        .upsert(entry.copyWith(isFavorite: !entry.isFavorite));
    await _load();
  }

  Future<void> _delete(LibraryEntry entry) async {
    await ref.read(servicesProvider).library.delete(entry.id);
    await _load();
  }

  Future<void> _importFile() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;
    final file = picked.single;
    final path = file.path ?? (file.uri.scheme == 'file' ? file.uri.toFilePath() : null);
    if (path == null) return;
    final kind = ContentRouter.kindOf(path);
    await ref.read(servicesProvider).library.upsert(LibraryEntry(
          id: Ids.newId('lib'),
          path: path,
          title: file.name,
          kind: kind.name,
          sizeBytes: await file.length() ?? 0,
          addedAtMs: DateTime.now().millisecondsSinceEpoch,
        ));
    await _load();
  }
}

class _LibraryTile extends StatelessWidget {
  final LibraryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDelete;
  const _LibraryTile({
    required this.entry,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final progress = entry.readingFraction;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        onTap: onOpen,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_iconFor(entry.kind), color: scheme.onSecondaryContainer),
        ),
        title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_kindLabel(entry.kind)} · ${Fmt.bytes(entry.sizeBytes)}'),
            if (progress > 0 && progress < 1) ...[
              const SizedBox(height: 6),
              StateProgress(value: progress, color: scheme.primary),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Favorite',
              onPressed: onToggleFavorite,
              icon: Icon(
                entry.isFavorite ? Icons.star : Icons.star_border,
                color: entry.isFavorite ? const Color(0xFFC9992A) : null,
              ),
            ),
            IconButton(tooltip: 'Remove from library', onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
          ],
        ),
      ),
    );
  }

  static String _kindLabel(String kind) => switch (kind) {
        'epub' => 'EPUB',
        'pdf' => 'PDF',
        'comicArchive' => 'Comic',
        'text' => 'Text',
        'video' => 'Video',
        'audio' => 'Audio',
        'image' => 'Image',
        _ => kind,
      };

  static IconData _iconFor(String kind) => switch (kind) {
        'epub' => Icons.menu_book_outlined,
        'pdf' => Icons.picture_as_pdf_outlined,
        'comicArchive' => Icons.auto_stories_outlined,
        'text' => Icons.description_outlined,
        'video' => Icons.movie_outlined,
        'audio' => Icons.music_note_outlined,
        'image' => Icons.image_outlined,
        _ => Icons.insert_drive_file_outlined,
      };
}
