/// Reading position for a book/comic. `locator` is an opaque, reader-defined
/// string (EPUB CFI, page index, scroll offset).
class ReadingPosition {
  final String contentId;
  final String locator;
  final double fraction;
  final int updatedAtMs;
  final int version;
  final String deviceId;

  const ReadingPosition({
    required this.contentId,
    required this.locator,
    required this.fraction,
    required this.updatedAtMs,
    this.version = 1,
    required this.deviceId,
  });

  Map<String, Object?> toMap() => {
        'content_id': contentId,
        'locator': locator,
        'fraction': fraction,
        'updated_at': updatedAtMs,
        'version': version,
        'device_id': deviceId,
      };

  static ReadingPosition fromMap(Map<String, Object?> m) => ReadingPosition(
        contentId: '${m['content_id']}',
        locator: '${m['locator']}',
        fraction: (m['fraction'] as num?)?.toDouble() ?? 0,
        updatedAtMs: (m['updated_at'] as int?) ?? 0,
        version: (m['version'] as int?) ?? 1,
        deviceId: '${m['device_id']}',
      );
}

class PlaybackPosition {
  final String contentId;
  final int positionMs;
  final int durationMs;
  final int updatedAtMs;

  const PlaybackPosition({
    required this.contentId,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAtMs,
  });

  double get fraction => durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0, 1);

  Map<String, Object?> toMap() => {
        'content_id': contentId,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'updated_at': updatedAtMs,
      };

  static PlaybackPosition fromMap(Map<String, Object?> m) => PlaybackPosition(
        contentId: '${m['content_id']}',
        positionMs: (m['position_ms'] as int?) ?? 0,
        durationMs: (m['duration_ms'] as int?) ?? 0,
        updatedAtMs: (m['updated_at'] as int?) ?? 0,
      );
}

class Bookmark {
  final String id;
  final String contentId;
  final String? label;
  final String locator;
  final int createdAtMs;

  const Bookmark({
    required this.id,
    required this.contentId,
    required this.locator,
    required this.createdAtMs,
    this.label,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'content_id': contentId,
        'label': label,
        'locator': locator,
        'created_at': createdAtMs,
      };

  static Bookmark fromMap(Map<String, Object?> m) => Bookmark(
        id: '${m['id']}',
        contentId: '${m['content_id']}',
        label: m['label'] as String?,
        locator: '${m['locator']}',
        createdAtMs: (m['created_at'] as int?) ?? 0,
      );
}

/// A queued offline write for a cloud provider. Retried with backoff; the
/// payload is a serialised SyncRecord. Never contains credentials.
class SyncQueueEntry {
  final int? id;
  final String op; // push | delete
  final String collection;
  final String recordKey;
  final String payloadJson;
  final int attempts;
  final int createdAtMs;

  const SyncQueueEntry({
    this.id,
    required this.op,
    required this.collection,
    required this.recordKey,
    required this.payloadJson,
    this.attempts = 0,
    required this.createdAtMs,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'op': op,
        'collection': collection,
        'record_key': recordKey,
        'payload': payloadJson,
        'attempts': attempts,
        'created_at': createdAtMs,
      };

  static SyncQueueEntry fromMap(Map<String, Object?> m) => SyncQueueEntry(
        id: m['id'] as int?,
        op: '${m['op']}',
        collection: '${m['collection']}',
        recordKey: '${m['record_key']}',
        payloadJson: '${m['payload']}',
        attempts: (m['attempts'] as int?) ?? 0,
        createdAtMs: (m['created_at'] as int?) ?? 0,
      );
}
