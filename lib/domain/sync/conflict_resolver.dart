import 'sync_models.dart';

enum SyncOutcome { keepLocal, takeRemote, merged }

class SyncResolution {
  final SyncOutcome outcome;
  final SyncRecord record;
  const SyncResolution(this.outcome, this.record);
}

/// Deterministic conflict resolution.
///
/// Rules, in order:
///  1. Higher `version` wins.
///  2. Equal versions break the tie on the newer `updatedAt`.
///  3. Still equal (same clock) → the lexicographically smaller `deviceId`
///     wins, so every device independently reaches the *same* answer.
///
/// For record types that are naturally mergeable (progress = max, bookmarks =
/// union) the caller passes a `merge` function and we produce a merged record
/// instead of picking a winner.
class SyncConflictResolver {
  final String localDeviceId;
  const SyncConflictResolver(this.localDeviceId);

  SyncResolution resolve(
    SyncRecord local,
    SyncRecord remote, {
    Map<String, Object?> Function(SyncRecord a, SyncRecord b)? merge,
  }) {
    if (merge != null) {
      final mergedPayload = merge(local, remote);
      final base = _winner(local, remote);
      return SyncResolution(
        SyncOutcome.merged,
        base.copyWith(payload: mergedPayload, version: (base.version) + 1),
      );
    }
    final winner = _winner(local, remote);
    final outcome = identical(winner, local) ? SyncOutcome.keepLocal : SyncOutcome.takeRemote;
    // Re-label: identity comparison works because _winner returns one of them.
    if (winner.key == local.key &&
        winner.version == local.version &&
        winner.updatedAt == local.updatedAt &&
        winner.deviceId == local.deviceId) {
      return SyncResolution(SyncOutcome.keepLocal, local);
    }
    return SyncResolution(outcome, winner);
  }

  SyncRecord _winner(SyncRecord a, SyncRecord b) {
    if (a.version != b.version) return a.version > b.version ? a : b;
    if (a.updatedAt != b.updatedAt) return a.updatedAt.isAfter(b.updatedAt) ? a : b;
    // Deterministic tie-break independent of which side is "local".
    final ids = [a.deviceId, b.deviceId]..sort();
    return a.deviceId == ids.first ? a : b;
  }

  /// Merge helpers for the record types we synchronise.
  static Map<String, Object?> mergeProgress(SyncRecord a, SyncRecord b) {
    final aFrac = _num(a.payload['fraction']);
    final bFrac = _num(b.payload['fraction']);
    final winner = aFrac >= bFrac ? a : b;
    return {...winner.payload, 'fraction': aFrac >= bFrac ? aFrac : bFrac};
  }

  static Map<String, Object?> mergeBookmarks(SyncRecord a, SyncRecord b) {
    final set = <String>{};
    for (final src in [a, b]) {
      final list = src.payload['bookmarks'];
      if (list is List) {
        for (final e in list) {
          set.add('$e');
        }
      }
    }
    final sorted = set.toList()..sort();
    return {'bookmarks': sorted};
  }

  static double _num(Object? v) => v is num ? v.toDouble() : 0.0;
}
