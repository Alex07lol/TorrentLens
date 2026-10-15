import 'package:sqflite/sqflite.dart';
import 'migrations.dart';

/// Owns the SQLite connection and applies [AppMigrations] on both create and
/// upgrade, so a fresh install and an upgraded install reach the same schema.
class AppDatabase {
  static const String fileName = 'torrentlens.db';
  final Database db;
  AppDatabase(this.db);

  static Future<AppDatabase> open({
    required DatabaseFactory factory,
    required String path,
  }) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: AppMigrations.latestVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          final batch = db.batch();
          for (final s in AppMigrations.statementsForCreate()) {
            batch.execute(s);
          }
          await batch.commit(noResult: true);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          final batch = db.batch();
          for (final s in AppMigrations.statementsForUpgrade(oldVersion, newVersion)) {
            batch.execute(s);
          }
          await batch.commit(noResult: true);
        },
      ),
    );
    return AppDatabase(db);
  }

  Future<void> close() => db.close();
}
