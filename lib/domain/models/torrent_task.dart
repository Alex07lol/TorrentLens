import '../torrent/task_state.dart';

/// A persisted torrent task. Speeds/bytes are stored as integers; formatting is
/// a UI concern.
class TorrentTask {
  final String id;
  final String? infoHashHex;
  final String name;
  final TorrentTaskState state;
  final String savePath;
  final int totalBytes;
  final int downloadedBytes;
  final int downloadBps;
  final int uploadBps;
  final int connectedPeers;
  final int addedAtMs;
  final int updatedAtMs;
  final String? errorMessage;
  final String sourceKind;
  final String? publisherId;
  final int? downloadLimitBps;
  final int? uploadLimitBps;
  final double? seedRatioLimit;
  final bool paused;

  const TorrentTask({
    required this.id,
    required this.infoHashHex,
    required this.name,
    required this.state,
    required this.savePath,
    required this.totalBytes,
    required this.downloadedBytes,
    required this.downloadBps,
    required this.uploadBps,
    required this.connectedPeers,
    required this.addedAtMs,
    required this.updatedAtMs,
    this.errorMessage,
    this.sourceKind = 'magnet',
    this.publisherId,
    this.downloadLimitBps,
    this.uploadLimitBps,
    this.seedRatioLimit,
    this.paused = false,
  });

  double get progress => totalBytes <= 0 ? 0 : (downloadedBytes / totalBytes).clamp(0, 1);

  TorrentTask copyWith({
    TorrentTaskState? state,
    int? downloadedBytes,
    int? downloadBps,
    int? uploadBps,
    int? connectedPeers,
    int? updatedAtMs,
    String? errorMessage,
    bool clearError = false,
    bool? paused,
    int? totalBytes,
    String? name,
  }) =>
      TorrentTask(
        id: id,
        infoHashHex: infoHashHex,
        name: name ?? this.name,
        state: state ?? this.state,
        savePath: savePath,
        totalBytes: totalBytes ?? this.totalBytes,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        downloadBps: downloadBps ?? this.downloadBps,
        uploadBps: uploadBps ?? this.uploadBps,
        connectedPeers: connectedPeers ?? this.connectedPeers,
        addedAtMs: addedAtMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        sourceKind: sourceKind,
        publisherId: publisherId,
        downloadLimitBps: downloadLimitBps,
        uploadLimitBps: uploadLimitBps,
        seedRatioLimit: seedRatioLimit,
        paused: paused ?? this.paused,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'info_hash': infoHashHex,
        'name': name,
        'state': state.name,
        'save_path': savePath,
        'total_bytes': totalBytes,
        'downloaded_bytes': downloadedBytes,
        'download_bps': downloadBps,
        'upload_bps': uploadBps,
        'connected_peers': connectedPeers,
        'added_at': addedAtMs,
        'updated_at': updatedAtMs,
        'error_message': errorMessage,
        'source_kind': sourceKind,
        'publisher_id': publisherId,
        'download_limit_bps': downloadLimitBps,
        'upload_limit_bps': uploadLimitBps,
        'seed_ratio_limit': seedRatioLimit,
        'paused': paused ? 1 : 0,
      };

  static TorrentTask fromMap(Map<String, Object?> m) => TorrentTask(
        id: '${m['id']}',
        infoHashHex: m['info_hash'] as String?,
        name: '${m['name']}',
        state: TorrentTaskState.values.firstWhere((s) => s.name == m['state'],
            orElse: () => TorrentTaskState.queued),
        savePath: '${m['save_path']}',
        totalBytes: (m['total_bytes'] as int?) ?? 0,
        downloadedBytes: (m['downloaded_bytes'] as int?) ?? 0,
        downloadBps: (m['download_bps'] as int?) ?? 0,
        uploadBps: (m['upload_bps'] as int?) ?? 0,
        connectedPeers: (m['connected_peers'] as int?) ?? 0,
        addedAtMs: (m['added_at'] as int?) ?? 0,
        updatedAtMs: (m['updated_at'] as int?) ?? 0,
        errorMessage: m['error_message'] as String?,
        sourceKind: '${m['source_kind'] ?? 'magnet'}',
        publisherId: m['publisher_id'] as String?,
        downloadLimitBps: m['download_limit_bps'] as int?,
        uploadLimitBps: m['upload_limit_bps'] as int?,
        seedRatioLimit: (m['seed_ratio_limit'] as num?)?.toDouble(),
        paused: (m['paused'] as int? ?? 0) == 1,
      );
}

class TorrentFileEntry {
  final String taskId;
  final int fileIndex;
  final String path;
  final int sizeBytes;
  final bool selected;
  final int priority;
  final int downloadedBytes;

  const TorrentFileEntry({
    required this.taskId,
    required this.fileIndex,
    required this.path,
    required this.sizeBytes,
    this.selected = true,
    this.priority = 4,
    this.downloadedBytes = 0,
  });

  Map<String, Object?> toMap() => {
        'task_id': taskId,
        'file_index': fileIndex,
        'path': path,
        'size_bytes': sizeBytes,
        'selected': selected ? 1 : 0,
        'priority': priority,
        'downloaded_bytes': downloadedBytes,
      };

  static TorrentFileEntry fromMap(Map<String, Object?> m) => TorrentFileEntry(
        taskId: '${m['task_id']}',
        fileIndex: (m['file_index'] as int?) ?? 0,
        path: '${m['path']}',
        sizeBytes: (m['size_bytes'] as int?) ?? 0,
        selected: (m['selected'] as int? ?? 1) == 1,
        priority: (m['priority'] as int?) ?? 4,
        downloadedBytes: (m['downloaded_bytes'] as int?) ?? 0,
      );
}
