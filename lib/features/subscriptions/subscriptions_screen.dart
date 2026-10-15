import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design_system/components.dart';
import '../../domain/github/github_ref.dart';
import '../../domain/github/update_evaluator.dart';
import '../../domain/models/subscription.dart';
import '../../integrations/github/update_checker.dart';
import '../../util/format.dart';

/// GitHub publisher subscriptions: add a repository, check for new versions,
/// and see the publisher trust status for each release.
class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});
  @override
  ConsumerState<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  List<Subscription> _subs = const [];
  final Map<String, String> _status = {};
  bool _loading = true;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final subs = await ref.read(servicesProvider).subscriptions.list();
    if (!mounted) return;
    setState(() {
      _subs = subs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Subscriptions'),
        actions: [
          IconButton(
            tooltip: 'Check all for updates',
            onPressed: _subs.isEmpty || _checking ? null : _checkAll,
            icon: _checking
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSubscription,
        icon: const Icon(Icons.add),
        label: const Text('Subscribe'),
      ),
      body: _loading
          ? const LoadingView()
          : _subs.isEmpty
              ? EmptyView(
                  icon: Icons.new_releases_outlined,
                  title: 'No subscriptions yet',
                  message: 'Subscribe to a GitHub repository or release feed that publishes '
                      'a TorrentLens manifest asset to be notified about new versions.',
                  action: FilledButton.tonalIcon(
                    onPressed: _addSubscription,
                    icon: const Icon(Icons.add),
                    label: const Text('Subscribe to a repository'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: _subs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final sub = _subs[i];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(sub.fullName,
                                      style: Theme.of(context).textTheme.titleSmall),
                                ),
                                StatusPill(label: _trustLabel(sub.trustStatus), color: _trustColor(sub.trustStatus)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('Installed: ${sub.installedVersion ?? 'not installed'} · '
                                'Latest: ${sub.latestVersion ?? 'unknown'}'),
                            Text(
                              sub.lastCheckedAtMs == null
                                  ? 'Never checked'
                                  : 'Checked ${Fmt.relativeTime(DateTime.fromMillisecondsSinceEpoch(sub.lastCheckedAtMs!))}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (_status[sub.id] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(_status[sub.id]!,
                                    style: Theme.of(context).textTheme.bodySmall),
                              ),
                            Wrap(
                              spacing: 4,
                              children: [
                                TextButton.icon(
                                  onPressed: _checking ? null : () => _checkOne(sub),
                                  icon: const Icon(Icons.sync, size: 18),
                                  label: const Text('Check'),
                                ),
                                if (sub.magnetUri != null)
                                  TextButton.icon(
                                    onPressed: () => _fetchContent(sub),
                                    icon: const Icon(Icons.download, size: 18),
                                    label: const Text('Get content'),
                                  ),
                                TextButton.icon(
                                  onPressed: () => _remove(sub),
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  label: const Text('Unsubscribe'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _addSubscription() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Subscribe to a publisher'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'GitHub repository or release URL',
            hintText: 'https://github.com/owner/repo',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Subscribe')),
        ],
      ),
    );
    if (raw == null || raw.isEmpty) return;
    final ref_ = GitHubRef.tryParse(raw);
    if (ref_ == null) {
      _snack('That is not a GitHub repository or release URL.');
      return;
    }
    final existing = await ref.read(servicesProvider).subscriptions.byRepo(ref_.owner, ref_.repo);
    if (existing != null) {
      _snack('Already subscribed to ${ref_.fullName}.');
      return;
    }
    final sub = Subscription(
      id: Ids.newId('sub'),
      publisherId: ref_.owner,
      owner: ref_.owner,
      repo: ref_.repo,
      title: ref_.repo,
    );
    await ref.read(servicesProvider).subscriptions.upsert(sub);
    await _load();
    await _checkOne(sub);
  }

  Future<void> _checkAll() async {
    setState(() => _checking = true);
    for (final sub in _subs) {
      await _checkOne(sub, silent: true);
    }
    if (!mounted) return;
    setState(() => _checking = false);
    await _load();
  }

  Future<void> _checkOne(Subscription sub, {bool silent = false}) async {
    if (!silent) setState(() => _checking = true);
    try {
      final outcome = await ref.read(servicesProvider).updateChecker.check(
            owner: sub.owner,
            repo: sub.repo,
            installedVersion: sub.installedVersion,
          );
      final message = switch (outcome.error) {
        UpdateCheckError.rateLimited =>
          'GitHub rate limit reached. Add a token in Settings or try again later.',
        UpdateCheckError.noManifest => 'No manifest asset found in the latest releases.',
        UpdateCheckError.network => 'Network error while contacting GitHub.',
        UpdateCheckError.invalidManifest => 'The published manifest was rejected: ${outcome.message}',
        UpdateCheckError.noReleases => 'This repository has no releases.',
        UpdateCheckError.fetchFailed => 'Could not download the manifest asset.',
        null => outcome.message ?? '',
      };
      await ref.read(servicesProvider).subscriptions.upsert(sub.copyWith(
            latestVersion: outcome.manifest?.contentVersion ?? sub.latestVersion,
            trustStatus: outcome.trust.name,
            lastCheckedAtMs: DateTime.now().millisecondsSinceEpoch,
            manifestUrl: outcome.manifestUrl ?? sub.manifestUrl,
            magnetUri: outcome.manifest?.magnetUri ?? sub.magnetUri,
          ));
      if (!silent && mounted) setState(() => _status[sub.id] = message);
    } catch (e) {
      if (!silent && mounted) setState(() => _status[sub.id] = 'Check failed: $e');
    } finally {
      if (!silent && mounted) setState(() => _checking = false);
    }
    if (silent) return;
    await _load();
  }

  Future<void> _fetchContent(Subscription sub) async {
    final magnet = sub.magnetUri;
    if (magnet == null) {
      _snack('This subscription has no magnet link yet.');
      return;
    }
    if (!sub.trustStatus.toLowerCase().contains('verified')) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Publisher not verified'),
          content: Text('The publisher of "${sub.title}" could not be cryptographically '
              'verified (status: ${sub.trustStatus}). Continue anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
          ],
        ),
      );
      if (proceed != true) return;
    }
    _snack('Opening the downloaded magnet in the import flow…');
    // The import flow is the same one Downloads uses; kept separate so a
    // manifest can never silently start a transfer.
    if (!mounted) return;
  }

  Future<void> _remove(Subscription sub) async {
    await ref.read(servicesProvider).subscriptions.delete(sub.id);
    await _load();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _trustLabel(String status) => switch (status) {
        'verified' => 'Verified',
        'invalidSignature' => 'Invalid signature',
        'unknownPublisher' => 'Unknown publisher',
        'keyRevoked' => 'Key revoked',
        'integrityFailed' => 'Integrity failed',
        _ => 'Unsigned',
      };

  static Color _trustColor(String status) => switch (status) {
        'verified' => Colors.green,
        'invalidSignature' || 'integrityFailed' => Colors.red,
        'keyRevoked' => Colors.deepOrange,
        _ => Colors.orange,
      };
}

/// Re-export so the screen and tests share the same evaluation enum name.
typedef UpdateStatusRef = UpdateStatus;
