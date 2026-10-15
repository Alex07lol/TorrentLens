import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design_system/components.dart';
import '../../domain/models/progress.dart';
import '../../integrations/reader/comic_source.dart';
import '../../navigation/route_args.dart';
import 'reader_state.dart';

/// Comic / image viewer for CBZ archives and loose images.
class ComicReaderScreen extends ConsumerStatefulWidget {
  final ReaderArgs args;
  const ComicReaderScreen({super.key, required this.args});
  @override
  ConsumerState<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends ConsumerState<ComicReaderScreen> {
  final _pageController = PageController();
  ComicArchive? _archive;
  Uint8List? _singleImage;
  int _page = 0;
  FitMode _fit = FitMode.contain;
  ReadingDirection _direction = ReadingDirection.leftToRight;
  String? _error;
  String? _note;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final path = widget.args.path;
      final lower = path.toLowerCase();
      if (lower.endsWith('.cbr') || lower.endsWith('.rar')) {
        setState(() => _error = null);
        _note = 'CBR/RAR comics are not supported: there is no maintained, '
            'permissively licensed RAR decoder for this build. Convert the archive to CBZ, '
            'or unrar it and open the image folder.';
        return;
      }
      final file = File(path);
      if (!file.existsSync()) throw Exception('File not found: $path');
      final bytes = await file.readAsBytes();

      if (ComicArchive.isImageFile(path)) {
        setState(() => _singleImage = bytes);
      } else {
        final archive = ComicArchive.open(bytes);
        if (archive.isEmpty) {
          throw Exception('No images found in this archive.');
        }
        setState(() => _archive = archive);
      }
      final saved = await ref.read(servicesProvider).progress.readingPosition(_contentId);
      if (saved != null && _archive != null) {
        final p = int.tryParse(saved.locator.replaceAll('page:', '')) ?? 0;
        setState(() => _page = p.clamp(0, _archive!.length - 1));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) _pageController.jumpToPage(_page);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  String get _contentId => widget.args.contentId ?? widget.args.path;

  Future<void> _persist() async {
    final archive = _archive;
    final total = archive?.length ?? 1;
    await ref.read(servicesProvider).progress.saveReadingPosition(ReadingPosition(
          contentId: _contentId,
          locator: 'page:$_page',
          fraction: total == 0 ? 0 : (_page + 1) / total,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          version: 1,
          deviceId: ref.read(servicesProvider).deviceId,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final archive = _archive;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.args.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'Fit', onPressed: _cycleFit, icon: const Icon(Icons.fit_screen)),
          IconButton(
            tooltip: 'Reading direction',
            onPressed: () => setState(() => _direction = _direction == ReadingDirection.leftToRight
                ? ReadingDirection.rightToLeft
                : ReadingDirection.leftToRight),
            icon: const Icon(Icons.swap_horiz),
          ),
        ],
        bottom: archive == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Text('${_page + 1} / ${archive.length} · ${archive.pageName(_page)}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _note != null
              ? EmptyView(icon: Icons.info_outline, title: 'Unsupported archive', message: _note)
              : _singleImage != null
                  ? _image(_singleImage!)
                  : archive == null
                      ? const LoadingView(label: 'Opening pages…')
                      : PageView.builder(
                          controller: _pageController,
                          reverse: _direction == ReadingDirection.rightToLeft,
                          itemCount: archive.length,
                          onPageChanged: (i) {
                            setState(() => _page = i);
                            _persist();
                          },
                          itemBuilder: (context, i) => _image(
                            Uint8List.fromList(archive.pageBytes(i)),
                          ),
                        ),
    );
  }

  Widget _image(Uint8List bytes) {
    if (bytes.isEmpty) {
      return const Center(child: Text('This page could not be decoded.'));
    }
    final child = Image.memory(bytes, gaplessPlayback: true, errorBuilder: (_, _, _) =>
        const Center(child: Text('This page could not be decoded.')));
    switch (_fit) {
      case FitMode.width:
        return SizedBox(width: double.infinity, child: child);
      case FitMode.height:
        return SizedBox(height: double.infinity, child: FittedBox(fit: BoxFit.contain, child: child));
      case FitMode.contain:
        return Center(child: InteractiveViewer(child: child));
    }
  }

  void _cycleFit() {
    setState(() {
      _fit = switch (_fit) {
        FitMode.contain => FitMode.width,
        FitMode.width => FitMode.height,
        FitMode.height => FitMode.contain,
      };
    });
  }
}
