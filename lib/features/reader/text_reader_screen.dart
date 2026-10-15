import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design_system/components.dart';
import '../../domain/models/progress.dart';
import '../../integrations/reader/text_paginator.dart';
import '../../navigation/route_args.dart';

/// Text and Markdown reader with stable pagination and resume.
class TextReaderScreen extends ConsumerStatefulWidget {
  final ReaderArgs args;
  const TextReaderScreen({super.key, required this.args});
  @override
  ConsumerState<TextReaderScreen> createState() => _TextReaderScreenState();
}

class _TextReaderScreenState extends ConsumerState<TextReaderScreen> {
  List<String> _pages = const [];
  int _page = 0;
  double _fontScale = 1.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _contentId => widget.args.contentId ?? widget.args.path;

  Future<void> _load() async {
    try {
      final file = File(widget.args.path);
      if (!file.existsSync()) throw Exception('File not found: ${widget.args.path}');
      final text = await file.readAsString();
      final pages = TextPaginator.paginate(text);
      final saved = await ref.read(servicesProvider).progress.readingPosition(_contentId);
      final page = saved == null ? 0 : int.tryParse(saved.locator.replaceAll('page:', '')) ?? 0;
      if (!mounted) return;
      setState(() {
        _pages = pages;
        _page = page.clamp(0, pages.length - 1);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _persist() async {
    await ref.read(servicesProvider).progress.saveReadingPosition(ReadingPosition(
          contentId: _contentId,
          locator: 'page:$_page',
          fraction: _pages.isEmpty ? 0 : (_page + 1) / _pages.length,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          version: 1,
          deviceId: ref.read(servicesProvider).deviceId,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.args.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'Text size', onPressed: _showFontSheet, icon: const Icon(Icons.format_size)),
        ],
        bottom: _pages.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Text('${_page + 1} / ${_pages.length}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _pages.isEmpty
              ? const LoadingView()
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        child: Text(
                          _pages[_page],
                          style: TextStyle(fontSize: 16 * _fontScale, height: 1.5),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _page > 0
                                ? () {
                                    setState(() => _page -= 1);
                                    _persist();
                                  }
                                : null,
                            icon: const Icon(Icons.chevron_left),
                            label: const Text('Previous'),
                          ),
                        ),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _page < _pages.length - 1
                                ? () {
                                    setState(() => _page += 1);
                                    _persist();
                                  }
                                : null,
                            icon: const Icon(Icons.chevron_right),
                            label: const Text('Next'),
                          ),
                        ),
                      ],
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
            ],
          ),
        ),
      ),
    );
  }
}
