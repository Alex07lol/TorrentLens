# Architecture

## Layers

```
Presentation   lib/features/**, lib/navigation/**, lib/design_system/**
Application    lib/app/** (AppServices container, Riverpod providers)
Domain         lib/domain/**   (pure Dart, no Flutter, no I/O)
Data           lib/data/**     (SQLite + migrations + repositories + secure store)
Integration    lib/integrations/** (torrent, github, manifests, cloud, media resolver, reader, web)
Native         android/app/src/main/kotlin/** (libtorrent4j engine + foreground service)
```

Screens depend on `AppServices` and on repository *interfaces*
(`lib/domain/repositories/repositories.dart`). They never touch SQLite, the
engine's internals, or an HTTP client directly. That is what keeps a screen
independent of which torrent engine or cloud provider is in use.

`lib/domain/**` is deliberately Flutter-free and I/O-free: it is the part that
can be unit-tested on the Dart VM and reused by a future platform port.

## Data flow: adding a torrent

```
DownloadsScreen
  -> TorrentImportService            (validation + orchestration)
     -> MagnetUri / TorrentSource     (domain parsing)
     -> TorrentEngine (MethodChannel) -> Kotlin TorrentEnginePlugin
        -> LibtorrentEngine           (libtorrent4j SessionManager)
        -> TorrentFileListSanitizer   (rejects hostile file names)
     -> TorrentTaskRepository         (SQLite: task + file list)
  -> polling tick reads engine.allStatus() and merges it over the DB row
```

The database is the source of truth for *what exists*; the engine is the source
of truth for *what is happening right now*. On launch the app reconciles them:
tasks persisted as active are re-registered rather than trusted blindly, and the
engine's real state is what the UI shows.

## Background execution

- A **foreground service** (`TorrentDownloadService`) keeps a user-initiated
  transfer alive with a visible, ongoing notification. Android requires this.
- **WorkManager** does *deferred* work: the periodic publisher update check
  (`features/subscriptions/update_worker.dart`). It is registered on Android at
  startup (`UpdateCheckScheduler.ensureScheduled`) and is explicitly **not** the
  transfer engine.
- TorrentLens never promises that a transfer continues under every Android
  power-management configuration. It re-syncs state on the next launch and says
  so in Settings.

## Tab workspace

The app's first destination is a browser-like tab workspace. The interesting part
is where the state lives:

```
TabManager (Riverpod Notifier)          features/browser/tab_manager.dart
  └─ TabSet        pure, immutable      domain/tabs/tab_set.dart
       ├─ BrowserTab / TabHistoryEntry  domain/tabs/browser_tab.dart
       ├─ TabRepository                 data/repositories/sqflite_repositories.dart
       │    └─ browser_tabs table       data/db/migrations.dart (v2)
       └─ TabRestoreService             features/browser/tab_restore_service.dart
TabContentHost                          features/browser/tab_content_host.dart
  └─ web/reader/player/torrent/...      the existing screens, unchanged
```

Rules that the implementation keeps:

- **All tab logic is pure.** `TabSet` is immutable and every operation
  (open, activate, close, back/forward, dedupe, resource budget, trim) is a
  function returning a new set, so it is unit-tested without a widget tree or a
  database. `TabManager` adds only persistence and debounced writes.
- **State updates are keyed by tab id.** A page reporting its title or loading
  state can only change its own tab; a `setLoading` on tab B cannot clear tab A's
  error.
- **Only durable metadata is stored.** A row holds a URL/path/id, a title, a
  history JSON blob, a scroll hint and the active flag. WebView controllers,
  players and buffers are created by `TabContentHost` and destroyed with the tab.
- **History belongs to the tab, not the WebView.** Back/forward move through the
  tab's own history and then tell the WebView to load that location. The
  trade-off is a reload instead of a back-forward cache; the benefit is history
  that survives process death and is testable.
- **Restore validates before it trusts.** `TabRestoreService` re-checks every
  address and file, keeps a broken tab's identity but attaches an error, and the
  host renders a recovery screen instead of a blank frame.
- **Live resources are budgeted.** At most `TabSet.defaultMaxLiveTabs` (6) tabs
  hold a WebView or player; the rest are evicted to a placeholder and reloaded
  when revisited.

Opening content is one path for every entry point:

```
Explorer / Library / torrent file list / media sheet
  -> ContentRouter.open(...)          (extension -> tab type)
     -> TabManager.openContent(...)   (dedupes: same file focuses the open tab)
     -> ShellTab.tabs                 (the workspace comes forward)
```

## Data flow: play while downloading

```
PlayerScreen
  └─ StreamingPlaybackController            (features/player/)
       ├─ StreamingPolicy                   (domain/torrent/streaming.dart)
       │    playhead byte -> piece range, contiguous-buffer maths, phases
       └─ TorrentEngine.beginStreaming / streamSnapshot / endStreaming
            └─ LibtorrentEngine             (android/.../torrent/)
                 ├─ StreamQuery.applyPriority  graded piece deadlines
                 └─ StreamQuery.snapshot       what is verified on disk
```

The split is deliberate: **policy in Dart, measurements natively**. The piece
arithmetic, the buffer depth rule and the phase machine are host-testable; the
Kotlin side only calls libtorrent and reports numbers. The player then reads the
local partial file, and the controller decides when that is safe.

## Media Link Resolver

Separate responsibilities, each independently testable:

| Component | Responsibility |
|---|---|
| `HtmlResourceExtractor` | anchors, media elements, `srcset`, `data-*` |
| `CssResourceExtractor` | `url()`, `@import` (resolved against the stylesheet) |
| `ScriptResourceAnalyzer` | static scan of script *text* — never executes it |
| `RedirectResolver` | hop-by-hop validation of every redirect |
| `MediaClassifier` | MIME + extension + structure → `MediaKind` |
| `StreamManifestParser` | HLS (`m3u8`) and DASH (`mpd`) manifests |
| `DrmCapabilityDetector` | recognises protection metadata; does not remove it |
| `AuthorizedPlaybackAdapter` | the only route to provider-authorised protected playback; the default fails closed |
| `MediaActionRouter` | `MediaKind` → in-app destination |
| `WebSandboxPolicy` | navigation policy for the HTML viewer |
| `PlaybackDiagnostics` | explains *why* playback failed |
| `StreamingPolicy` | piece window, buffer depth, stall detection for play-while-downloading |

Discovery is static by default. JavaScript is never executed just to find links.

## Security boundaries

- `lib/domain/security/**` holds URL policy, SHA-256 integrity, Ed25519
  verification, archive-path safety and the trusted-key registry.
- Downloaded files and manifests are treated as untrusted data everywhere.
- Credentials live in `flutter_secure_storage`; the SQLite database holds no
  secrets.

See [security.md](security.md).
