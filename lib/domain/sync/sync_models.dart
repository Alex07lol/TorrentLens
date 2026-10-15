/// A single synchronisable record. `version` is a monotonic counter used for
/// conflict resolution; `updatedAt` breaks ties. Nothing here is a secret —
/// credentials live in the secure store, never in a sync payload.
class SyncRecord {
  final String key;
  final String type;
  final Map<String, Object?> payload;
  final int version;
  final DateTime updatedAt;
  final String deviceId;

  const SyncRecord({
    required this.key,
    required this.type,
    required this.payload,
    required this.version,
    required this.updatedAt,
    required this.deviceId,
  });

  SyncRecord copyWith({Map<String, Object?>? payload, int? version, DateTime? updatedAt}) =>
      SyncRecord(
        key: key,
        type: type,
        payload: payload ?? this.payload,
        version: version ?? this.version,
        updatedAt: updatedAt ?? this.updatedAt,
        deviceId: deviceId,
      );

  Map<String, Object?> toJson() => {
        'key': key,
        'type': type,
        'payload': payload,
        'version': version,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deviceId': deviceId,
      };

  static SyncRecord? fromJson(Map<String, Object?> j) {
    final key = j['key'];
    final version = j['version'];
    final updatedAt = DateTime.tryParse('${j['updatedAt']}');
    if (key is! String || version is! int || updatedAt == null) return null;
    return SyncRecord(
      key: key,
      type: '${j['type']}',
      payload: (j['payload'] as Map?)?.cast<String, Object?>() ?? const {},
      version: version,
      updatedAt: updatedAt,
      deviceId: '${j['deviceId']}',
    );
  }
}
