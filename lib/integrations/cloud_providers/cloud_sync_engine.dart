import '../../domain/cloud/cloud_contracts.dart';
import '../../domain/sync/conflict_resolver.dart';
import '../../domain/sync/sync_models.dart';

class SyncReport {
  final int pulled;
  final int pushed;
  final int merged;
  final int unchanged;
  final List<String> errors;
  /// Records the caller should persist locally (remote winners and merges).
  final Map<String, SyncRecord> localUpdates;

  const SyncReport({
    this.pulled = 0,
    this.pushed = 0,
    this.merged = 0,
    this.unchanged = 0,
    this.errors = const [],
    this.localUpdates = const {},
  });

  bool get hadErrors => errors.isNotEmpty;

  SyncReport merge(SyncReport o) => SyncReport(
        pulled: pulled + o.pulled,
        pushed: pushed + o.pushed,
        merged: merged + o.merged,
        unchanged: unchanged + o.unchanged,
        errors: [...errors, ...o.errors],
        localUpdates: {...localUpdates, ...o.localUpdates},
      );
}

/// Local-first synchronisation.
///
/// Guarantees:
///  * Never deletes local data on a failed sync — only makes *additive* writes.
///  * Idempotent: records carry a monotonic version, so re-running is a no-op.
///  * A failure in one collection is recorded, not thrown, so the rest proceed.
///  * Deterministic conflicts via [SyncConflictResolver] (same answer on every
///    device), with per-type merge strategies for progress/bookmarks.
class SyncEngine {
  final CloudProvider provider;
  final SyncConflictResolver resolver;
  final Map<String, Map<String, Object?> Function(SyncRecord, SyncRecord)> mergeStrategies;

  SyncEngine(this.provider, String localDeviceId, {this.mergeStrategies = const {}})
      : resolver = SyncConflictResolver(localDeviceId);

  Future<SyncReport> sync(Map<String, SyncRecord> local, List<String> collections) async {
    var report = const SyncReport();
    for (final collection in collections) {
      final remote = await provider.pull(collection);
      if (remote.isErr) {
        report = report.merge(SyncReport(errors: ['$collection: ${remote.errorOrNull()}']));
        continue;
      }
      final remoteByKey = <String, SyncRecord>{
        for (final r in remote.valueOrNull!)
          if (r.type == collection) r.key: r
      };

      // Remote-only records are pulled in; local-only records are pushed.
      for (final e in remoteByKey.entries) {
        if (!local.containsKey(e.key)) {
          report = report.merge(SyncReport(pulled: 1, localUpdates: {e.key: e.value}));
        }
      }

      for (final entry in local.entries) {
        final l = entry.value;
        if (l.type != collection) continue;
        final r = remoteByKey[l.key];
        if (r == null) {
          final pushed = await provider.push(l);
          report = report.merge(pushed.isErr
              ? SyncReport(errors: ['push ${l.key}: ${pushed.errorOrNull()}'])
              : const SyncReport(pushed: 1));
          continue;
        }
        final resolution = resolver.resolve(l, r, merge: mergeStrategies[collection]);
        switch (resolution.outcome) {
          case SyncOutcome.keepLocal:
            if (_differs(l, r)) {
              final next = l.copyWith(version: r.version + 1);
              final pushed = await provider.push(next);
              report = report.merge(pushed.isErr
                  ? SyncReport(errors: ['push ${l.key}: ${pushed.errorOrNull()}'])
                  : SyncReport(pushed: 1, localUpdates: {l.key: next}));
            } else {
              report = report.merge(const SyncReport(unchanged: 1));
            }
          case SyncOutcome.takeRemote:
            report = report.merge(SyncReport(pulled: 1, localUpdates: {l.key: r}));
          case SyncOutcome.merged:
            final pushed = await provider.push(resolution.record);
            report = report.merge(pushed.isErr
                ? SyncReport(errors: ['push merged ${l.key}: ${pushed.errorOrNull()}'])
                : SyncReport(merged: 1, pushed: 1, localUpdates: {l.key: resolution.record}));
        }
      }
    }
    return report;
  }

  bool _differs(SyncRecord a, SyncRecord b) =>
      a.version != b.version ||
      a.updatedAt != b.updatedAt ||
      a.payload.toString() != b.payload.toString();
}
