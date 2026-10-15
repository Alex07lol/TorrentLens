import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/domain/sync/conflict_resolver.dart';
import 'package:torrentlens/domain/sync/sync_models.dart';

SyncRecord rec(String key, int version, String updatedAt, String device, Map<String, Object?> payload) =>
    SyncRecord(
      key: key,
      type: 'reading_progress',
      payload: payload,
      version: version,
      updatedAt: DateTime.parse(updatedAt),
      deviceId: device,
    );

void main() {
  const resolver = SyncConflictResolver('device-a');

  test('higher version wins regardless of recency', () {
    final local = rec('k', 5, '2026-01-01T00:00:00Z', 'device-a', {'fraction': 0.2});
    final remote = rec('k', 6, '2025-01-01T00:00:00Z', 'device-b', {'fraction': 0.9});
    final r = resolver.resolve(local, remote);
    expect(r.outcome, SyncOutcome.takeRemote);
    expect(r.record.version, 6);
  });

  test('equal versions break the tie on the newer timestamp', () {
    final local = rec('k', 3, '2026-02-01T00:00:00Z', 'device-a', {'fraction': 0.5});
    final remote = rec('k', 3, '2026-01-01T00:00:00Z', 'device-b', {'fraction': 0.1});
    expect(resolver.resolve(local, remote).outcome, SyncOutcome.keepLocal);
  });

  test('a full tie resolves deterministically and symmetrically', () {
    final a = rec('k', 3, '2026-01-01T00:00:00Z', 'device-a', {'fraction': 0.5});
    final b = rec('k', 3, '2026-01-01T00:00:00Z', 'device-b', {'fraction': 0.5});
    final fromA = resolver.resolve(a, b).record.deviceId;
    final fromB = const SyncConflictResolver('device-b').resolve(b, a).record.deviceId;
    expect(fromA, fromB); // both devices agree on the winner
    expect(fromA, 'device-a'); // lexicographically smaller id
  });

  test('progress merges by taking the max fraction', () {
    final local = rec('k', 4, '2026-01-01T00:00:00Z', 'device-a', {'fraction': 0.3, 'chapter': 2});
    final remote = rec('k', 4, '2026-01-01T00:00:00Z', 'device-b', {'fraction': 0.8, 'chapter': 2});
    final r = resolver.resolve(local, remote, merge: SyncConflictResolver.mergeProgress);
    expect(r.outcome, SyncOutcome.merged);
    expect(r.record.payload['fraction'], 0.8);
  });

  test('bookmarks merge as a sorted union', () {
    final local = rec('k', 1, '2026-01-01T00:00:00Z', 'device-a', {'bookmarks': ['a', 'c']});
    final remote = rec('k', 1, '2026-01-01T00:00:00Z', 'device-b', {'bookmarks': ['b', 'c']});
    final r = resolver.resolve(local, remote, merge: SyncConflictResolver.mergeBookmarks);
    expect(r.record.payload['bookmarks'], ['a', 'b', 'c']);
  });

  test('round-trips through JSON and rejects malformed records', () {
    final r = rec('k', 2, '2026-01-01T00:00:00Z', 'device-a', {'fraction': 0.5});
    final back = SyncRecord.fromJson(r.toJson())!;
    expect(back.key, 'k');
    expect(back.version, 2);
    expect(SyncRecord.fromJson({'key': 'x'}), isNull);
  });
}
