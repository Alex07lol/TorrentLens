/// Ordered, additive schema migrations.
///
/// Each entry is one schema version. Migrations are never edited once shipped:
/// a new change appends a new entry. That is what makes upgrades safe — the
/// same statements run whether the database is created fresh or upgraded.
class Migration {
  final int version;
  final List<String> statements;
  const Migration(this.version, this.statements);
}

class AppMigrations {
  static const List<Migration> all = [
    Migration(1, [
      '''
      CREATE TABLE torrent_tasks (
        id TEXT PRIMARY KEY,
        info_hash TEXT,
        name TEXT NOT NULL,
        state TEXT NOT NULL,
        save_path TEXT NOT NULL,
        total_bytes INTEGER NOT NULL DEFAULT 0,
        downloaded_bytes INTEGER NOT NULL DEFAULT 0,
        download_bps INTEGER NOT NULL DEFAULT 0,
        upload_bps INTEGER NOT NULL DEFAULT 0,
        connected_peers INTEGER NOT NULL DEFAULT 0,
        added_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        error_message TEXT,
        source_kind TEXT NOT NULL DEFAULT 'magnet',
        publisher_id TEXT,
        download_limit_bps INTEGER,
        upload_limit_bps INTEGER,
        seed_ratio_limit REAL,
        paused INTEGER NOT NULL DEFAULT 0
      )
      ''',
      'CREATE INDEX idx_tasks_state ON torrent_tasks(state)',
      'CREATE INDEX idx_tasks_info_hash ON torrent_tasks(info_hash)',
      '''
      CREATE TABLE torrent_files (
        task_id TEXT NOT NULL,
        file_index INTEGER NOT NULL,
        path TEXT NOT NULL,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        selected INTEGER NOT NULL DEFAULT 1,
        priority INTEGER NOT NULL DEFAULT 4,
        downloaded_bytes INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (task_id, file_index),
        FOREIGN KEY (task_id) REFERENCES torrent_tasks(id) ON DELETE CASCADE
      )
      ''',
      '''
      CREATE TABLE subscriptions (
        id TEXT PRIMARY KEY,
        publisher_id TEXT NOT NULL,
        owner TEXT NOT NULL,
        repo TEXT NOT NULL,
        title TEXT NOT NULL,
        installed_version TEXT,
        latest_version TEXT,
        trust_status TEXT NOT NULL DEFAULT 'unsigned',
        last_checked_at INTEGER,
        check_interval_hours INTEGER NOT NULL DEFAULT 24,
        auto_download INTEGER NOT NULL DEFAULT 0,
        manifest_url TEXT,
        magnet_uri TEXT
      )
      ''',
      'CREATE UNIQUE INDEX idx_subs_repo ON subscriptions(owner, repo)',
      '''
      CREATE TABLE library_entries (
        id TEXT PRIMARY KEY,
        path TEXT NOT NULL,
        title TEXT NOT NULL,
        kind TEXT NOT NULL,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        source_task_id TEXT,
        publisher_id TEXT,
        added_at INTEGER NOT NULL,
        last_opened_at INTEGER,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        reading_fraction_ppm INTEGER
      )
      ''',
      'CREATE INDEX idx_library_kind ON library_entries(kind)',
      'CREATE INDEX idx_library_task ON library_entries(source_task_id)',
      '''
      CREATE TABLE reading_positions (
        content_id TEXT PRIMARY KEY,
        locator TEXT NOT NULL,
        fraction REAL NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        device_id TEXT NOT NULL
      )
      ''',
      '''
      CREATE TABLE playback_positions (
        content_id TEXT PRIMARY KEY,
        position_ms INTEGER NOT NULL DEFAULT 0,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
      ''',
      '''
      CREATE TABLE bookmarks (
        id TEXT PRIMARY KEY,
        content_id TEXT NOT NULL,
        label TEXT,
        locator TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
      ''',
      'CREATE INDEX idx_bookmarks_content ON bookmarks(content_id)',
      '''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        op TEXT NOT NULL,
        collection TEXT NOT NULL,
        record_key TEXT NOT NULL,
        payload TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
      ''',
      '''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
      ''',
    ]),
  ];

  static int get latestVersion => all.last.version;

  /// Flattened statements for a fresh database.
  static List<String> statementsForCreate() =>
      all.expand((m) => m.statements).toList();

  /// Statements needed to upgrade from [from] to [to].
  static List<String> statementsForUpgrade(int from, int to) => all
      .where((m) => m.version > from && m.version <= to)
      .expand((m) => m.statements)
      .toList();
}
