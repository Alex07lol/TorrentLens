/// A file the user can open from the Library / Explorer.
class LibraryEntry {
  final String id;
  final String path;
  final String title;
  final String kind;
  final int sizeBytes;
  final String? sourceTaskId;
  final String? publisherId;
  final int addedAtMs;
  final int? lastOpenedAtMs;
  final bool isFavorite;
  final int? readingFractionPpm; // parts-per-million to keep it an int

  const LibraryEntry({
    required this.id,
    required this.path,
    required this.title,
    required this.kind,
    required this.sizeBytes,
    this.sourceTaskId,
    this.publisherId,
    required this.addedAtMs,
    this.lastOpenedAtMs,
    this.isFavorite = false,
    this.readingFractionPpm,
  });

  double get readingFraction => (readingFractionPpm ?? 0) / 1000000.0;

  LibraryEntry copyWith({
    String? title,
    int? lastOpenedAtMs,
    bool? isFavorite,
    int? readingFractionPpm,
    int? sizeBytes,
  }) =>
      LibraryEntry(
        id: id,
        path: path,
        title: title ?? this.title,
        kind: kind,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        sourceTaskId: sourceTaskId,
        publisherId: publisherId,
        addedAtMs: addedAtMs,
        lastOpenedAtMs: lastOpenedAtMs ?? this.lastOpenedAtMs,
        isFavorite: isFavorite ?? this.isFavorite,
        readingFractionPpm: readingFractionPpm ?? this.readingFractionPpm,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'path': path,
        'title': title,
        'kind': kind,
        'size_bytes': sizeBytes,
        'source_task_id': sourceTaskId,
        'publisher_id': publisherId,
        'added_at': addedAtMs,
        'last_opened_at': lastOpenedAtMs,
        'is_favorite': isFavorite ? 1 : 0,
        'reading_fraction_ppm': readingFractionPpm,
      };

  static LibraryEntry fromMap(Map<String, Object?> m) => LibraryEntry(
        id: '${m['id']}',
        path: '${m['path']}',
        title: '${m['title']}',
        kind: '${m['kind']}',
        sizeBytes: (m['size_bytes'] as int?) ?? 0,
        sourceTaskId: m['source_task_id'] as String?,
        publisherId: m['publisher_id'] as String?,
        addedAtMs: (m['added_at'] as int?) ?? 0,
        lastOpenedAtMs: m['last_opened_at'] as int?,
        isFavorite: (m['is_favorite'] as int? ?? 0) == 1,
        readingFractionPpm: m['reading_fraction_ppm'] as int?,
      );
}
