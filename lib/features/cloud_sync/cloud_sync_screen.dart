import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/result.dart';
import '../../domain/models/progress.dart';
import '../../data/secure/secure_store.dart';
import '../../design_system/components.dart';
import '../../domain/cloud/cloud_contracts.dart';
import '../../domain/manifests/manifest_validator.dart';
import '../../domain/manifests/source_manifest.dart';
import '../../domain/security/signatures.dart';
import '../../domain/sync/sync_models.dart';
import '../../integrations/cloud_providers/cloud_registry.dart';
import '../../integrations/cloud_providers/cloud_sync_engine.dart';

/// Optional, publisher-operated cloud synchronisation.
///
/// Local-first is the default: with no provider connected everything still
/// works. Connecting is explicit, the data types are listed, and disconnecting
/// clears only the sync state — never the user's library.
class CloudSyncScreen extends ConsumerStatefulWidget {
  const CloudSyncScreen({super.key});
  @override
  ConsumerState<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends ConsumerState<CloudSyncScreen> {
  PublisherConfig? _config;
  String? _lastSyncSummary;
  bool _busy = false;
  String? _error;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = ref.read(servicesProvider);
    final raw = await s.settings.get('cloud.provider');
    _pending = await s.syncQueue.count();
    if (raw != null) {
      try {
        final map = (jsonDecode(raw) as Map).cast<String, Object?>();
        final result = PublisherConfig.fromManifest(CloudProviderConfig(
          providerType: '${map['providerType']}',
          endpoint: '${map['endpoint']}',
          protocolVersion: (map['protocolVersion'] as num).toInt(),
          schemaVersion: (map['schemaVersion'] as num).toInt(),
          capabilities: (map['capabilities'] as List?)?.map((e) => '$e').toList() ?? const [],
          authMethod: '${map['authMethod']}',
          scopes: const [],
          publisherIdentity: map['publisherIdentity'] as String?,
        ));
        if (result.isOk) {
          _config = result.valueOrNull;
        }
      } catch (_) {
        // Corrupt config: fall back to "not connected".
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud sync')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          SectionCard(
            title: 'How this works',
            child: Text(
              'TorrentLens does not operate a central database. A publisher may host its own '
              'backend and describe it in its manifest. Connecting is optional; if you never '
              'connect one, your reading progress, bookmarks and downloads stay on this device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          if (_config == null)
            SectionCard(
              title: 'Connect a publisher backend',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Paste a manifest URL from a publisher that offers cloud sync.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _connectFromManifest,
                    icon: const Icon(Icons.link),
                    label: const Text('Add manifest URL'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            )
          else
            SectionCard(
              title: 'Connected provider',
              trailing: StatusPill(label: _config!.providerType, color: Colors.blue),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_config!.endpoint.toString(), style: Theme.of(context).textTheme.bodySmall),
                  Text('Protocol v${_config!.protocolVersion} · schema v${_config!.schemaVersion}'),
                  Text('Capabilities: ${_config!.capabilities.join(', ')}'),
                  Text('Auth: ${_config!.authMethod}'),
                  const SizedBox(height: 8),
                  Text('Pending queued writes: $_pending'),
                  if (_lastSyncSummary != null) ...[
                    const SizedBox(height: 8),
                    Text(_lastSyncSummary!),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _syncNow,
                        icon: _busy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.sync),
                        label: const Text('Sync now'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _disconnect,
                        icon: const Icon(Icons.link_off),
                        label: const Text('Disconnect'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'What gets synced',
            child: const Text(
              '• Reading positions\n'
              '• Bookmarks\n\n'
              'Files, browsing history and downloads are never uploaded.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connectFromManifest() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publisher manifest URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'https://…/manifest.json'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Load')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = ref.read(servicesProvider);
      final response = await s.fetcher.get(Uri.parse(url), maxBytes: 1024 * 1024);
      if (response.statusCode >= 400) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final parsed = ManifestValidator.parse(jsonDecode(response.body));
      if (parsed.isErr) throw Exception('Manifest rejected: ${parsed.errorOrNull()}');
      final manifest = parsed.valueOrNull!;
      if (manifest.cloud == null) {
        throw Exception('That publisher manifest does not declare a cloud backend.');
      }
      final verified = await PublisherSignatureVerifier.verify(
        messageBytes: PublisherSignatureVerifier.canonicalize(manifest.signablePayload()),
        signatureBase64: manifest.signature,
        keyId: manifest.signingKeyId,
        registry: s.trustedKeys,
      );
      if (!verified.status.isTrusted) {
        final proceed = await _confirm(
            'Publisher not verified',
            'Trust status: ${verified.status.label}. Connect to this backend anyway?');
        if (!proceed) return;
      }
      final config = PublisherConfig.fromManifest(manifest.cloud!);
      if (config.isErr) throw Exception('${config.errorOrNull()}');
      final cfg = config.valueOrNull!;

      var anonKey = await s.secure.read(SecureKeys.supabaseAnonKey(cfg.endpoint.host));
      if (cfg.providerType == 'supabase' && (anonKey == null || anonKey.isEmpty)) {
        final key = await _promptSecret('Supabase anon key',
            'Use the project\'s public anon key. Never paste a service-role key.');
        if (key == null || key.isEmpty) throw Exception('An anon key is required for Supabase.');
        anonKey = key;
        await s.secure.write(SecureKeys.supabaseAnonKey(cfg.endpoint.host), key);
      }

      await s.settings.set('cloud.provider', jsonEncode(manifest.cloud!.toJson()));
      setState(() => _config = cfg);
      _snack('Connected to ${cfg.providerType}.');
    } catch (e) {
      setState(() => _error = 'Could not connect: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    final cfg = _config;
    if (cfg == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = ref.read(servicesProvider);
      final key = await s.secure.read(SecureKeys.supabaseAnonKey(cfg.endpoint.host));
      final registry = CloudProviderRegistries.standard(
        fetcher: s.fetcher,
        supabaseAnonKey: (_) => key,
        supabaseAccessToken: () => null,
      );
      final auth = _AnonymousAuth();
      final providerResult = registry.create(cfg, auth);
      if (providerResult.isErr) throw Exception('${providerResult.errorOrNull()}');
      final provider = providerResult.valueOrNull!;

      // Build local sync records from the database.
      final positions = await s.progress.allReadingPositions();
      final local = <String, SyncRecord>{};
      for (final p in positions) {
        local[p.contentId] = SyncRecord(
          key: p.contentId,
          type: 'reading_positions',
          payload: {'locator': p.locator, 'fraction': p.fraction},
          version: p.version,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(p.updatedAtMs),
          deviceId: s.deviceId,
        );
      }

      final engine = SyncEngine(provider, s.deviceId);
      final report = await engine.sync(local, ['reading_positions']);

      // Apply pulled/merged records locally.
      for (final entry in report.localUpdates.entries) {
        final rec = entry.value;
        await s.progress.saveReadingPosition(ReadingPosition(
          contentId: rec.key,
          locator: '${rec.payload['locator']}',
          fraction: (rec.payload['fraction'] as num?)?.toDouble() ?? 0,
          updatedAtMs: rec.updatedAt.millisecondsSinceEpoch,
          version: rec.version,
          deviceId: rec.deviceId,
        ));
      }
      _lastSyncSummary =
          'Last sync: pulled ${report.pulled}, pushed ${report.pushed}, merged ${report.merged}, '
          'unchanged ${report.unchanged}${report.hadErrors ? ' (${report.errors.length} error(s))' : ''}';
      _pending = await s.syncQueue.count();
      await _load();
    } catch (e) {
      setState(() => _error = 'Sync failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await _confirm('Disconnect provider?',
        'Removes the saved provider configuration and clears the sync queue. Your library and local progress are kept.');
    if (!ok) return;
    final s = ref.read(servicesProvider);
    await s.settings.set('cloud.provider', '');
    for (final entry in await s.syncQueue.pending(limit: 1000)) {
      await s.syncQueue.remove(entry.id!);
    }
    setState(() {
      _config = null;
      _lastSyncSummary = null;
    });
    await _load();
  }

  Future<bool> _confirm(String title, String message) async =>
      (await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
          ],
        ),
      )) ??
      false;

  Future<String?> _promptSecret(String title, String hint) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(hint, style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(controller: controller, obscureText: true, autofocus: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Anonymous auth for public read data; a real sign-in would live here.
class _AnonymousAuth implements CloudAuthAdapter {
  @override
  String get method => 'none';
  @override
  bool get isAuthenticated => true;
  @override
  Future<Result<void>> signIn() async => const Ok(null);
  @override
  Future<void> signOut() async {}
}
