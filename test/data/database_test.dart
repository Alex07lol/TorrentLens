import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:torrentlens/data/db/app_database.dart';
import 'package:torrentlens/data/db/migrations.dart';
import 'package:torrentlens/data/repositories/sqflite_repositories.dart';
import 'package:torrentlens/data/secure/secure_store.dart';
import 'package:torrentlens/domain/models/library_entry.dart';
import 'package:torrentlens/domain/models/progress.dart';
import 'package:torrentlens/domain/models/subscription.dart';
import 'package:torrentlens/domain/models/torrent_task.dart';
import 'package:torrentlens/domain/torrent/task_state.dart';

const task = TorrentTask(
  id: 't1',
  infoHashHex: '0123456789abcdef0123456789abcdef01234567',
  name: 'Example',
  state: TorrentTaskState.downloading,
  savePath: '/data/downloads',
  totalBytes: 1000,
  downloadedBytes: 250,
  downloadBps: 10,
  uploadBps: 1,
  connectedPeers: 3,
  addedAtMs: 1,
  updatedAtMs: 2,
  seedRatioLimit: 1.5,
);

void main() {
  setUpAll(sqfliteFfiInit);

  Future<AppDatabase> openMemory() =>
      AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);

  test('migrations: create covers the latest version, upgrade is additive', () {
    expect(AppMigrations.latestVersion, 1);
    expect(AppMigrations.statementsForUpgrade(0, 1), AppMigrations.statementsForCreate());
    expect(AppMigrations.statementsForUpgrade(1, 1), isEmpty);
  });

  test('fresh database creates every expected table', () async {
    final app = await openMemory();
    final tables = await app.db
        .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final names = tables.map((r) => '${r['name']}').toSet();
    for (final t in [
      'torrent_tasks',
      'torrent_files',
      'subscriptions',
      'library_entries',
      'reading_positions',
      'playback_positions',
      'bookmarks',
      'sync_queue',
      'app_settings',
    ]) {
      expect(names, contains(t), reason: 'missing table $t');
    }
    await app.close();
  });

  test('torrent task + file repositories round-trip and cascade', () async {
    final app = await openMemory();
    final tasks = SqfliteTorrentTaskRepository(app.db);
    await tasks.upsertTask(task);
    final loaded = await tasks.taskById('t1');
    expect(loaded!.name, 'Example');
    expect(loaded.seedRatioLimit, 1.5);
    expect(loaded.state, TorrentTaskState.downloading);
    expect(loaded.progress, closeTo(0.25, 1e-9));

    await tasks.replaceFiles('t1', const [
      TorrentFileEntry(taskId: 't1', fileIndex: 0, path: 'a.mkv', sizeBytes: 100),
      TorrentFileEntry(taskId: 't1', fileIndex: 1, path: 'b.srt', sizeBytes: 5, selected: false, priority: 0),
    ]);
    var files = await tasks.filesFor('t1');
    expect(files.length, 2);
    await tasks.setFileSelected('t1', 1, true);
    files = await tasks.filesFor('t1');
    expect(files[1].selected, isTrue);

    // replacing is idempotent (no duplicate rows)
    await tasks.replaceFiles('t1', const [
      TorrentFileEntry(taskId: 't1', fileIndex: 0, path: 'a.mkv', sizeBytes: 100),
    ]);
    expect((await tasks.filesFor('t1')).length, 1);

    // FK cascade removes child rows
    await tasks.deleteTask('t1');
    expect(await tasks.filesFor('t1'), isEmpty);
    await app.close();
  });

  test('subscription repository tracks due checks and trust', () async {
    final app = await openMemory();
    final subs = SqfliteSubscriptionRepository(app.db);
    await subs.upsert(const Subscription(
        id: 's1', publisherId: 'pub', owner: 'owner', repo: 'repo', title: 'Repo',
        installedVersion: '1.0.0', trustStatus: 'verified', checkIntervalHours: 6));
    expect((await subs.byRepo('owner', 'repo'))!.installedVersion, '1.0.0');
    // never checked -> due
    expect((await subs.dueForCheck(DateTime.now().millisecondsSinceEpoch)).length, 1);
    await subs.upsert((await subs.byRepo('owner', 'repo'))!
        .copyWith(lastCheckedAtMs: DateTime.now().millisecondsSinceEpoch));
    expect((await subs.dueForCheck(DateTime.now().millisecondsSinceEpoch)), isEmpty);
    await subs.delete('s1');
    expect(await subs.list(), isEmpty);
    await app.close();
  });

  test('library repository supports search, filters and recents', () async {
    final app = await openMemory();
    final lib = SqfliteLibraryRepository(app.db);
    await lib.upsert(LibraryEntry(
        id: 'l1', path: '/x/book.epub', title: 'A Book', kind: 'epub',
        sizeBytes: 10, addedAtMs: 1, isFavorite: true));
    await lib.upsert(LibraryEntry(
        id: 'l2', path: '/x/comic.cbz', title: 'A Comic', kind: 'comicArchive',
        sizeBytes: 20, addedAtMs: 2));
    expect((await lib.list()).length, 2);
    expect((await lib.list(kind: 'epub')).single.id, 'l1');
    expect((await lib.list(search: 'comic')).single.id, 'l2');
    expect((await lib.list(favoritesOnly: true)).single.id, 'l1');
    await lib.touchOpened('l2', 99);
    expect((await lib.recentlyOpened()).single.id, 'l2');
    await app.close();
  });

  test('progress: reading position mirrors onto the library entry', () async {
    final app = await openMemory();
    final progress = SqfliteProgressRepository(app.db);
    final lib = SqfliteLibraryRepository(app.db);
    await lib.upsert(LibraryEntry(
        id: 'c1', path: '/x/book.epub', title: 'Book', kind: 'epub',
        sizeBytes: 1, addedAtMs: 1));
    await progress.saveReadingPosition(const ReadingPosition(
        contentId: 'c1', locator: 'epubcfi(/6/4)', fraction: 0.42, updatedAtMs: 5, deviceId: 'd1'));
    expect((await progress.readingPosition('c1'))!.fraction, closeTo(0.42, 1e-9));
    expect((await lib.byId('c1'))!.readingFractionPpm, 420000);

    await progress.savePlaybackPosition(const PlaybackPosition(
        contentId: 'v1', positionMs: 30000, durationMs: 60000, updatedAtMs: 7));
    expect((await progress.playbackPosition('v1'))!.fraction, closeTo(0.5, 1e-9));

    await progress.addBookmark(
        const Bookmark(id: 'b1', contentId: 'c1', locator: 'p42', createdAtMs: 9, label: 'Chapter 5'));
    expect((await progress.bookmarksFor('c1')).single.label, 'Chapter 5');
    await progress.removeBookmark('b1');
    expect(await progress.bookmarksFor('c1'), isEmpty);
    await app.close();
  });

  test('settings and sync queue repositories work and are idempotent', () async {
    final app = await openMemory();
    final settings = SqfliteSettingsRepository(app.db);
    await settings.set('theme', 'dark');
    await settings.set('theme', 'light');
    expect(await settings.get('theme'), 'light');
    expect((await settings.all())['theme'], 'light');

    final queue = SqfliteSyncQueueRepository(app.db);
    await queue.enqueue(SyncQueueEntry(
        op: 'push', collection: 'reading_progress', recordKey: 'k',
        payloadJson: '{}', createdAtMs: 1));
    await queue.enqueue(SyncQueueEntry(
        op: 'delete', collection: 'bookmarks', recordKey: 'b',
        payloadJson: '{}', createdAtMs: 2));
    expect(await queue.count(), 2);
    final pending = await queue.pending();
    expect(pending.first.op, 'push');
    await queue.markAttempt(pending.first.id!, 3);
    expect((await queue.pending()).first.attempts, 3);
    await queue.remove(pending.first.id!);
    expect(await queue.count(), 1);
    await app.close();
  });

  test('data survives a close/reopen (persistence, not just in-memory)', () async {
    final dir = await Directory.systemTemp.createTemp('torrentlens-db');
    final path = '${dir.path}/app.db';
    try {
      final a = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      await SqfliteSettingsRepository(a.db).set('k', 'v');
      await a.close();

      final b = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      expect(await SqfliteSettingsRepository(b.db).get('k'), 'v');
      // Reopening at the same version must not re-run migrations (no error).
      expect((await b.db.query('app_settings')).length, 1);
      await b.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('secure store abstraction keeps secrets out of the database', () async {
    final store = InMemorySecureStore();
    await store.write(SecureKeys.githubToken, 'secret-token');
    expect(await store.read(SecureKeys.githubToken), 'secret-token');
    await store.delete(SecureKeys.githubToken);
    expect(await store.read(SecureKeys.githubToken), isNull);
  });
}
