import '../models/library_entry.dart';
import '../models/progress.dart';
import '../models/subscription.dart';
import '../models/torrent_task.dart';

/// Repository contracts. The data layer implements them over SQLite; screens
/// depend on these interfaces, never on the database directly.
abstract class TorrentTaskRepository {
  Future<List<TorrentTask>> listTasks({bool includeCompleted = true});
  Future<TorrentTask?> taskById(String id);
  Future<void> upsertTask(TorrentTask task);
  Future<void> deleteTask(String id);
  Future<List<TorrentFileEntry>> filesFor(String taskId);
  Future<void> replaceFiles(String taskId, List<TorrentFileEntry> files);
  Future<void> setFileSelected(String taskId, int fileIndex, bool selected);
}

abstract class SubscriptionRepository {
  Future<List<Subscription>> list();
  Future<Subscription?> byRepo(String owner, String repo);
  Future<void> upsert(Subscription sub);
  Future<void> delete(String id);
  Future<List<Subscription>> dueForCheck(int nowMs);
}

abstract class LibraryRepository {
  Future<List<LibraryEntry>> list({String? kind, String? search, bool favoritesOnly = false});
  Future<LibraryEntry?> byId(String id);
  Future<void> upsert(LibraryEntry entry);
  Future<void> delete(String id);
  Future<void> touchOpened(String id, int nowMs);
  Future<List<LibraryEntry>> recentlyOpened({int limit = 20});
}

abstract class ProgressRepository {
  Future<ReadingPosition?> readingPosition(String contentId);
  Future<void> saveReadingPosition(ReadingPosition position);
  Future<List<ReadingPosition>> allReadingPositions();
  Future<PlaybackPosition?> playbackPosition(String contentId);
  Future<void> savePlaybackPosition(PlaybackPosition position);
  Future<List<Bookmark>> bookmarksFor(String contentId);
  Future<void> addBookmark(Bookmark bookmark);
  Future<void> removeBookmark(String id);
}

abstract class SettingsRepository {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
  Future<Map<String, String>> all();
}

abstract class SyncQueueRepository {
  Future<void> enqueue(SyncQueueEntry entry);
  Future<List<SyncQueueEntry>> pending({int limit = 100});
  Future<void> markAttempt(int id, int attempts);
  Future<void> remove(int id);
  Future<int> count();
}
