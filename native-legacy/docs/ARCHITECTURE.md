# TorrentLens — architecture

Android-first. Kotlin + Jetpack Compose, a native BitTorrent engine, Room for
persistence, and a security model that treats every downloaded byte as hostile.

```
app/                     Compose UI, navigation, ViewModel, DI, service, workers
 ├─ ui/screens           Dashboard, Downloads, Library, Subscriptions, Settings
 ├─ ui/reader            Touch reader (EPUB / PDF / CBZ / CBR / image / text)
 ├─ ui/import            Torrent import sheet (magnet, URL, .torrent, folder)
 ├─ data                 TorrentImporter, SubscriptionManager, ReaderContentLoader
 ├─ service              TorrentDownloadService (foreground, dataSync)
 └─ work                 ManifestCheckWorker, BootCompletedReceiver

core/domain/             PURE KOTLIN/JVM — no Android. The rules live here.
 ├─ torrent              magnet/torrent parsing, info-hash, file-list sanitizer
 ├─ github               ref parsing, semver, manifest discovery, update evaluation
 ├─ security             SafePaths (zip-slip), SHA-256 integrity, Ed25519 signatures
 └─ util                 strict RFC 3986 percent decoding

core/data/               Room entities, DAOs, repositories, DataStore settings
core/github/             OkHttp GitHub client + verified update checker
core/torrent/            libtorrent4j engine binding behind a Kotlin interface
core/reader/             EPUB container/OPF, PDF, CBZ/CBR, text, isolated WebView
```

## Why the dependency direction matters

`core:domain` has **no Android dependency at all**. That is what makes the
security-critical rules (path traversal, hash and signature verification, version
comparison, input parsing) unit-testable on a plain JVM — and they are: 72 tests
run in seconds, with no device or emulator. It is also the module a future
Windows/Linux client reuses unchanged.

`core:torrent` exposes `TorrentEngine`, so libtorrent4j is an implementation
detail. Swapping to another maintained binding would not touch the UI, the
database or the notification layer.

## Background execution

| Work | Mechanism | Why |
|---|---|---|
| Active, user-initiated transfer | Foreground service, `dataSync` type | Must keep running while the app is backgrounded; needs a visible, accurate notification |
| Periodic release checks | WorkManager (unique periodic, ≥15 min) | Deferrable, connectivity-gated, tolerant of delay |

The service stops itself when nothing is actively transferring rather than
holding a foreground slot with a misleading notification. No component claims a
download continues indefinitely.

## Storage

Torrent payload is written to app-specific external storage (no permission
required); user-chosen folders are reached through the Storage Access Framework
and used as export targets. `MANAGE_EXTERNAL_STORAGE` is deliberately never
requested.

## Security

See `docs/adr/0005-security-model.md`. Summary: strict input parsing, path
traversal rejection for torrent file lists and archive entries, SHA-256 integrity
plus detached Ed25519 verification against a **pinned** trust root that the
manifest cannot supply, and an isolated WebView (no file/content access, no JS
bridge) for downloaded HTML.
