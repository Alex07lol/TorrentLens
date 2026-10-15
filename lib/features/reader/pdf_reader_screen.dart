import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/providers.dart';
import '../../design_system/components.dart';
import '../../domain/models/progress.dart';
import '../../navigation/route_args.dart';

/// PDF viewer backed by pdfrx (PDFium). Malformed PDFs surface as an error
/// rather than a crash; the last read page is restored and saved.
class PdfReaderScreen extends ConsumerStatefulWidget {
  final ReaderArgs args;
  const PdfReaderScreen({super.key, required this.args});
  @override
  ConsumerState<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends ConsumerState<PdfReaderScreen> {
  int _initialPage = 1;
  int _currentPage = 1;
  int _pageCount = 0;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  String get _contentId => widget.args.contentId ?? widget.args.path;

  Future<void> _restore() async {
    try {
      final saved = await ref.read(servicesProvider).progress.readingPosition(_contentId);
      if (saved == null) return;
      final page = int.tryParse(saved.locator.replaceAll('page:', '')) ?? 1;
      if (!mounted) return;
      setState(() {
        _initialPage = page;
        _currentPage = page;
      });
    } catch (_) {}
  }

  Future<void> _persist() async {
    if (_pageCount == 0) return;
    await ref.read(servicesProvider).progress.saveReadingPosition(ReadingPosition(
          contentId: _contentId,
          locator: 'page:$_currentPage',
          fraction: _currentPage / _pageCount,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          version: 1,
          deviceId: ref.read(servicesProvider).deviceId,
        ));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.args.title)),
        body: ErrorView(message: _error!),
      );
    }
    final file = File(widget.args.path);
    if (!file.existsSync()) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.args.title)),
        body: ErrorView(message: 'File not found: ${widget.args.path}'),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.args.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: _pageCount == 0
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Text('Page $_currentPage of $_pageCount',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
        actions: [
          if (!_ready)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
      body: PdfViewer.file(
        widget.args.path,
        initialPageNumber: _initialPage,
        params: PdfViewerParams(
          onViewerReady: (document, controller) {
            if (!mounted) return;
            setState(() {
              _ready = true;
              _pageCount = document.pages.length;
            });
          },
          onPageChanged: (page) {
            if (page == null) return;
            _currentPage = page;
            _persist();
          },
          errorBannerBuilder: (context, error, stackTrace, documentRef) =>
              Center(child: Text('This PDF could not be rendered: $error')),
          loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
              const LoadingView(label: 'Loading PDF...'),
        ),
      ),
    );
  }
}
