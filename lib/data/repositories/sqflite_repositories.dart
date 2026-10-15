import 'package:sqflite/sqflite.dart';
import '../../domain/models/library_entry.dart';
import '../../domain/models/progress.dart';
import '../../domain/models/subscription.dart';
import '../../domain/models/torrent_task.dart';
import '../../domain/repositories/repositories.dart';

class SqfliteTorrentTaskRepository implements TorrentTaskRepository {
  final Database db;
  SqfliteTorrentTaskRepository(this.db);

  static const _active = "state NOT IN ('completed','failed','unavailable')";

  @override
  Future<List<TorrentTask>> listTasks({bool includeCompleted = true}) async {
    final rows = await db.query('torrent_tasks',
        where: includeCompleted ? null : _active, orderBy: 'added_at DESC');
    return rows.map(TorrentTask.fromMap).toList();
  }

  @override
  Future<TorrentTask?> taskById(String id) async {
    final rows = await db.query('torrent_tasks', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : TorrentTask.fromMap(rows.first);
  }

  @override
  Future<void> upsertTask(TorrentTask task) async {
    await db.insert('torrent_tasks', task.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteTask(String id) async {
    await db.delete('torrent_tasks', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<TorrentFileEntry>> filesFor(String taskId) async {
    final rows = await db.query('torrent_files',
        where: 'task_id = ?', whereArgs: [taskId], orderBy: 'file_index ASC');
    return rows.map(TorrentFileEntry.fromMap).toList();
  }

  @override
  Future<void> replaceFiles(String taskId, List<TorrentFileEntry> files) async {
    await db.transaction((txn) async {
      await txn.delete('torrent_files', where: 'task_id = ?', whereArgs: [taskId]);
      final batch = txn.batch();
      for (final f in files) {
        batch.insert('torrent_files', f.toMap());
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> setFileSelected(String taskId, int fileIndex, bool selected) async {
    await db.update('torrent_files', {'selected': selected ? 1 : 0},
        where: 'task_id = ? AND file_index = ?', whereArgs: [taskId, fileIndex]);
  }
}

class SqfliteSubscriptionRepository implements SubscriptionRepository {
  final Database db;
  SqfliteSubscriptionRepository(this.db);

  @override
  Future<List<Subscription>> list() async {
    final rows = await db.query('subscriptions', orderBy: 'title COLLATE NOCASE ASC');
    return rows.map(Subscription.fromMap).toList();
  }

  @override
  Future<Subscription?> byRepo(String owner, String repo) async {
    final rows = await db.query('subscriptions',
        where: 'owner = ? AND repo = ?', whereArgs: [owner, repo], limit: 1);
    return rows.isEmpty ? null : Subscription.fromMap(rows.first);
  }

  @override
  Future<void> upsert(Subscription sub) async {
    await db.insert('subscriptions', sub.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete(String id) async {
    await db.delete('subscriptions', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<Subscription>> dueForCheck(int nowMs) async {
    final rows = await db.query('subscriptions');
    return rows
        .map(Subscription.fromMap)
        .where((s) => s.lastCheckedAtMs == null ||
            nowMs >= s.lastCheckedAtMs! + s.checkIntervalHours * 3600 * 1000)
        .toList();
  }
}

class SqfliteLibraryRepository implements LibraryRepository {
  final Database db;
  SqfliteLibraryRepository(this.db);

  @override
  Future<List<LibraryEntry>> list(
      {String? kind, String? search, bool favoritesOnly = false}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind);
    }
    if (favoritesOnly) where.add('is_favorite = 1');
    if (search != null && search.trim().isNotEmpty) {
      where.add('title LIKE ?');
      args.add('%${search.trim()}%');
    }
    final rows = await db.query('library_entries',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'title COLLATE NOCASE ASC');
    return rows.map(LibraryEntry.fromMap).toList();
  }

  @override
  Future<LibraryEntry?> byId(String id) async {
    final rows = await db.query('library_entries', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : LibraryEntry.fromMap(rows.first);
  }

  @override
  Future<void> upsert(LibraryEntry entry) async {
    await db.insert('library_entries', entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete(String id) async {
    await db.delete('library_entries', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> touchOpened(String id, int nowMs) async {
    await db.update('library_entries', {'last_opened_at': nowMs},
        where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<LibraryEntry>> recentlyOpened({int limit = 20}) async {
    final rows = await db.query('library_entries',
        where: 'last_opened_at IS NOT NULL',
        orderBy: 'last_opened_at DESC',
        limit: limit);
    return rows.map(LibraryEntry.fromMap).toList();
  }
}

class SqfliteProgressRepository implements ProgressRepository {
  final Database db;
  SqfliteProgressRepository(this.db);

  @override
  Future<ReadingPosition?> readingPosition(String contentId) async {
    final rows = await db.query('reading_positions',
        where: 'content_id = ?', whereArgs: [contentId], limit: 1);
    return rows.isEmpty ? null : ReadingPosition.fromMap(rows.first);
  }

  @override
  Future<void> saveReadingPosition(ReadingPosition position) async {
    await db.insert('reading_positions', position.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    // Mirror onto the library entry so the Library can show progress cheaply.
    await db.update(
        'library_entries',
        {'reading_fraction_ppm': (position.fraction * 1000000).round()},
        where: 'id = ?',
        whereArgs: [position.contentId]);
  }

  @override
  Future<List<ReadingPosition>> allReadingPositions() async {
    final rows = await db.query('reading_positions');
    return rows.map(ReadingPosition.fromMap).toList();
  }

  @override
  Future<PlaybackPosition?> playbackPosition(String contentId) async {
    final rows = await db.query('playback_positions',
        where: 'content_id = ?', whereArgs: [contentId], limit: 1);
    return rows.isEmpty ? null : PlaybackPosition.fromMap(rows.first);
  }

  @override
  Future<void> savePlaybackPosition(PlaybackPosition position) async {
    await db.insert('playback_positions', position.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<Bookmark>> bookmarksFor(String contentId) async {
    final rows = await db.query('bookmarks',
        where: 'content_id = ?', whereArgs: [contentId], orderBy: 'created_at DESC');
    return rows.map(Bookmark.fromMap).toList();
  }

  @override
  Future<void> addBookmark(Bookmark bookmark) async {
    await db.insert('bookmarks', bookmark.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> removeBookmark(String id) async {
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }
}

class SqfliteSettingsRepository implements SettingsRepository {
  final Database db;
  SqfliteSettingsRepository(this.db);

  @override
  Future<String?> get(String key) async {
    final rows = await db.query('app_settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : '${rows.first['value']}';
  }

  @override
  Future<void> set(String key, String value) async {
    await db.insert('app_settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<Map<String, String>> all() async {
    final rows = await db.query('app_settings');
    return {for (final r in rows) '${r['key']}': '${r['value']}'};
  }
}

class SqfliteSyncQueueRepository implements SyncQueueRepository {
  final Database db;
  SqfliteSyncQueueRepository(this.db);

  @override
  Future<void> enqueue(SyncQueueEntry entry) async {
    await db.insert('sync_queue', entry.toMap());
  }

  @override
  Future<List<SyncQueueEntry>> pending({int limit = 100}) async {
    final rows = await db.query('sync_queue', orderBy: 'created_at ASC', limit: limit);
    return rows.map(SyncQueueEntry.fromMap).toList();
  }

  @override
  Future<void> markAttempt(int id, int attempts) async {
    await db.update('sync_queue', {'attempts': attempts}, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> remove(int id) async {
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<int> count() async {
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM sync_queue');
    return Sqflite.firstIntValue(r) ?? 0;
  }
}
