import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db/app_database.dart';
import '../data/repositories/sqflite_repositories.dart';
import '../data/secure/secure_store.dart';
import '../domain/cloud/cloud_contracts.dart';
import '../domain/media/drm.dart';
import '../domain/repositories/repositories.dart';
import '../domain/security/trusted_keys.dart';
import '../integrations/cloud_providers/cloud_registry.dart';
import '../integrations/github/github_client.dart';
import '../integrations/github/update_checker.dart';
import '../integrations/media_resolver/media_link_resolver.dart';
import '../integrations/net/http_fetcher_io.dart';
import '../integrations/torrent/torrent_engine.dart';
import '../util/format.dart';

/// The dependency container for the whole app. Built once at startup and
/// exposed through [servicesProvider]; screens never construct clients
/// themselves, which keeps them independent of engine/provider internals.
class AppServices {
  final AppDatabase db;
  final TorrentTaskRepository torrents;
  final SubscriptionRepository subscriptions;
  final LibraryRepository library;
  final ProgressRepository progress;
  final SettingsRepository settings;
  final SyncQueueRepository syncQueue;

  final TorrentEngine engine;
  final HttpFetcherImpl fetcher;
  final GitHubClient github;
  final UpdateChecker updateChecker;
  final CloudProviderRegistry cloudRegistry;
  final TrustedKeyRegistry trustedKeys;
  final SecureStore secure;
  final MediaLinkResolver resolver;

  /// The boundary for provider-authorised DRM playback. Defaults to the
  /// fail-closed adapter: the app never claims protected content will play.
  final AuthorizedPlaybackAdapter authorizedPlayback;

  final String deviceId;
  final String defaultDownloadDir;

  AppServices({
    required this.db,
    required this.torrents,
    required this.subscriptions,
    required this.library,
    required this.progress,
    required this.settings,
    required this.syncQueue,
    required this.engine,
    required this.fetcher,
    required this.github,
    required this.updateChecker,
    required this.cloudRegistry,
    required this.trustedKeys,
    required this.secure,
    required this.resolver,
    this.authorizedPlayback = const UnconfiguredAuthorizedPlaybackAdapter(),
    required this.deviceId,
    required this.defaultDownloadDir,
  });

  static Future<AppServices> open() async {
    final dbDir = await getDatabasesPath();
    final db = await AppDatabase.open(
      factory: databaseFactory,
      path: '$dbDir/${AppDatabase.fileName}',
    );
    final settings = SqfliteSettingsRepository(db.db);
    final secure = KeystoreSecureStore();

    // Stable per-install device id (used for deterministic sync tie-breaks).
    var deviceId = await settings.get('device.id');
    if (deviceId == null) {
      deviceId = Ids.newId('dev');
      await settings.set('device.id', deviceId);
    }

    // App-specific external storage: a real filesystem path, no permission
    // required. A user-chosen SAF folder can override this in Settings.
    final external = await getExternalStorageDirectory();
    final defaultDownloadDir = external?.path ?? (await getApplicationDocumentsDirectory()).path;

    final fetcher = HttpFetcherImpl();
    final trustedKeys = InMemoryTrustedKeyRegistry(kPinnedPublisherKeys);
    final githubToken = await secure.read(SecureKeys.githubToken);
    final github = GitHubClient(fetcher, token: githubToken);

    final cloudRegistry = CloudProviderRegistries.standard(
      fetcher: fetcher,
      includeMock: false,
      supabaseAnonKey: (providerId) => null, // filled from secure storage per provider
      supabaseAccessToken: () => null,
    );

    return AppServices(
      db: db,
      torrents: SqfliteTorrentTaskRepository(db.db),
      subscriptions: SqfliteSubscriptionRepository(db.db),
      library: SqfliteLibraryRepository(db.db),
      progress: SqfliteProgressRepository(db.db),
      settings: settings,
      syncQueue: SqfliteSyncQueueRepository(db.db),
      engine: MethodChannelTorrentEngine(),
      fetcher: fetcher,
      github: github,
      updateChecker: UpdateChecker(github, trustedKeys),
      cloudRegistry: cloudRegistry,
      trustedKeys: trustedKeys,
      secure: secure,
      resolver: MediaLinkResolver(fetcher),
      deviceId: deviceId,
      defaultDownloadDir: defaultDownloadDir,
    );
  }

  Future<void> dispose() async {
    await db.close();
    fetcher.close();
  }
}
