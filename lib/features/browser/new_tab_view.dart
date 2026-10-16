import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/tabs/browser_address.dart';
import '../../domain/tabs/browser_tab.dart';
import '../../navigation/shell.dart';
import '../downloads/torrent_import_service.dart';
import '../home/home_screen.dart';
import 'tab_manager.dart';

/// What a blank tab shows: address entry, one-tap routes into the rest of the
/// app, and the live dashboard. Reusing [HomeScreen] here means the "home" the
/// user knew is now the new-tab page instead of a separate destination.
class NewTabView extends ConsumerStatefulWidget {
  const NewTabView({super.key});

  @override
  ConsumerState<NewTabView> createState() => _NewTabViewState();
}

class _NewTabViewState extends ConsumerState<NewTabView> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: TextField(
            key: const Key('new-tab-address'),
            textInputAction: TextInputAction.go,
            autocorrect: false,
            keyboardType: TextInputType.url,
            onSubmitted: _go,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search, enter an address, or paste a magnet link',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ),
        _QuickActions(enabled: !_busy),
        const Divider(height: 1),
        const Expanded(child: HomeScreen()),
      ],
    );
  }

  Future<void> _go(String raw) async {
    final input = raw.trim();
    if (input.isEmpty) return;
    final parsed = BrowserAddress.parse(input);

    if (parsed.isMagnet) {
      await _addMagnet(input);
      return;
    }
    final url = parsed.url;
    if (url == null) {
      _say(parsed.rejection ?? 'That address could not be understood.');
      return;
    }
    // The blank tab becomes the web tab: that is what a browser does when you
    // type an address into a fresh tab.
    ref.read(tabManagerProvider.notifier).navigate(
          location: url.toString(),
          title: url.host.isEmpty ? url.toString() : url.host,
          type: BrowserTabType.web,
          push: false,
        );
  }

  /// Magnets go through exactly the same import service as the Downloads screen
  /// — one code path, one set of error messages.
  Future<void> _addMagnet(String magnet) async {
    setState(() => _busy = true);
    try {
      final result = await TorrentImportService(ref.read(servicesProvider)).addMagnet(magnet);
      if (!mounted) return;
      if (!result.ok) {
        _say(result.error ?? 'That magnet link could not be added.');
        return;
      }
      final hash = result.infoHash;
      if (hash != null) {
        ref.read(tabManagerProvider.notifier).openTorrent(
              infoHash: hash,
              title: 'Torrent ${hash.substring(0, 8)}',
              taskId: result.taskId,
            );
      }
      _say('Magnet added. Metadata is resolving in the Downloads tab.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _QuickActions extends ConsumerWidget {
  final bool enabled;
  const _QuickActions({required this.enabled});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shell = ref.read(shellIndexProvider.notifier);
    final manager = ref.read(tabManagerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('New tab'),
            onPressed: enabled ? () => manager.openHomeTab() : null,
          ),
          ActionChip(
            avatar: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Downloads'),
            onPressed: enabled ? () => shell.set(ShellTab.downloads) : null,
          ),
          ActionChip(
            avatar: const Icon(Icons.folder_outlined, size: 18),
            label: const Text('Explorer'),
            onPressed: enabled ? () => shell.set(ShellTab.explorer) : null,
          ),
          ActionChip(
            avatar: const Icon(Icons.collections_bookmark_outlined, size: 18),
            label: const Text('Library'),
            onPressed: enabled ? () => shell.set(ShellTab.library) : null,
          ),
          ActionChip(
            avatar: const Icon(Icons.new_releases_outlined, size: 18),
            label: const Text('Subscriptions'),
            onPressed: enabled ? () => shell.set(ShellTab.subscriptions) : null,
          ),
          ActionChip(
            avatar: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('Settings'),
            onPressed: enabled ? () => shell.set(ShellTab.settings) : null,
          ),
        ],
      ),
    );
  }
}
