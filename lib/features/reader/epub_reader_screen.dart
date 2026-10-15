import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/services.dart';
import '../../app/providers.dart';
import '../../design_system/components.dart';
import '../../domain/models/progress.dart';
import '../../integrations/reader/epub_parser.dart';
import '../../integrations/reader/text_paginator.dart';
import '../../navigation/route_args.dart';
import '../../util/format.dart';

/// EPUB reader: chapter navigation, pagination, font sizing, bookmarks and
/// resume. Parsing is the app's own (see [EpubParser]); it does not execute any
/// content from the book.
class EpubReaderScreen extends ConsumerStatefulWidget {
  final ReaderArgs args;
  const EpubReaderScreen({super.key, required this.args});
  @override
  ConsumerState<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends ConsumerState<EpubReaderScreen> {
  EpubBook? _book;
  List<String> _pages = const [];
  int _chapter = 0;
  int _page = 0;
  double _fontScale = 1.0;
  String? _error;
  String _bookmarkLocator = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.args.path);
      if (!file.existsSync()) {
        throw Exception('File not found: ${widget.args.path}');
      }
      final bytes = await file.readAsBytes();
      final book = EpubParser.parse(bytes);
      final saved = await _services.progress.readingPosition(_contentId);
      var chapter = 0;
      var page = 0;
      if (saved != null) {
        final parts = saved.locator.split(':');
        if (parts.length == 4 && parts[0] == 'ch') {
          chapter = int.tryParse(parts[1]) ?? 0;
          page = int.tryParse(parts[3]) ?? 0;
        }
      }
      if (!mounted) return;
      setState(() {
        _book = book;
        _chapter = chapter.clamp(0, book.chapters.length - 1);
        _pages = TextPaginator.paginate(_book!.chapters[_chapter].text);
        _page = page.clamp(0, _pages.length - 1);
      });
      _persist();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  AppServices get _services => ref.read(servicesProvider);
  String get _contentId => widget.args.contentId ?? widget.args.path;

  void _goToChapter(int index) {
    if (_book == null) return;
    setState(() {
      _chapter = index.clamp(0, _book!.chapters.length - 1);
      _pages = TextPaginator.paginate(_book!.chapters[_chapter].text);
      _page = 0;
    });
    _persist();
  }

  void _turnPage(int delta) {
    final next = _page + delta;
    if (next < 0) {
      if (_chapter > 0) {
        setState(() {
          _chapter -= 1;
          _pages = TextPaginator.paginate(_book!.chapters[_chapter].text);
          _page = _pages.length - 1;
        });
        _persist();
      }
      return;
    }
    if (next >= _pages.length) {
      if (_chapter < (_book!.chapters.length - 1)) {
        _goToChapter(_chapter + 1);
      }
      return;
    }
    setState(() => _page = next);
    _persist();
  }

  Future<void> _persist() async {
    final book = _book;
    if (book == null || _pages.isEmpty) return;
    final total = book.chapters.length;
    final fraction = ((_chapter + (_page / _pages.length)) / total).clamp(0.0, 1.0);
    final locator = 'ch:$_chapter:p:$_page';
    _bookmarkLocator = locator;
    await _services.progress.saveReadingPosition(ReadingPosition(
      contentId: _contentId,
      locator: locator,
      fraction: fraction,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      version: 1,
      deviceId: _services.deviceId,
    ));
  }

  Future<void> _addBookmark() async {
    await _services.progress.addBookmark(Bookmark(
      id: Ids.newId('bm'),
      contentId: _contentId,
      label: _book?.chapters[_chapter].title,
      locator: _bookmarkLocator,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Bookmark added.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Scaffold(appBar: AppBar(title: Text(widget.args.title)), body: ErrorView(message: _error!, onRetry: _load));
    final book = _book;
    if (book == null) {
      return Scaffold(appBar: AppBar(title: Text(widget.args.title)), body: const LoadingView(label: 'Opening book…'));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'Bookmark', onPressed: _addBookmark, icon: const Icon(Icons.bookmark_add_outlined)),
          IconButton(tooltip: 'Toggle dark reading theme',
              onPressed: () => setState(() {}), icon: const Icon(Icons.contrast)),
          IconButton(
            tooltip: 'Text size',
            onPressed: _showFontSheet,
            icon: const Icon(Icons.format_size),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    book.chapters[_chapter].title,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('${_page + 1}/${_pages.length}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              if (book.author != null)
                ListTile(title: Text(book.author!), subtitle: Text(book.title)),
              const Divider(),
              for (var i = 0; i < book.chapters.length; i++)
                ListTile(
                  selected: i == _chapter,
                  title: Text(book.chapters[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(context);
                    _goToChapter(i);
                  },
                ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Text(
                  _pages.isEmpty ? '' : _pages[_page],
                  style: TextStyle(
                    fontSize: 17 * _fontScale,
                    height: 1.55,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _turnPage(-1),
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Previous'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _turnPage(1),
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Next'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFontSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Text size', style: Theme.of(ctx).textTheme.titleMedium),
              Slider(
                value: _fontScale,
                min: 0.8,
                max: 2.0,
                divisions: 12,
                label: '${(_fontScale * 100).round()}%',
                onChanged: (v) {
                  setSheet(() {});
                  setState(() => _fontScale = v);
                },
              ),
              TextButton(
                onPressed: () => setState(() => _fontScale = 1.0),
                child: const Text('Reset'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
