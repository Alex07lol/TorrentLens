# TorrentLens

An **Android-first, local-first** application that combines a browser-style
multi-tab workspace, a genuine BitTorrent client, a content explorer, document
readers (EPUB/PDF/CBZ/images/text), a media player, an HTML/website viewer with
media-link discovery, GitHub-powered publisher subscriptions, and an **optional**
publisher-owned cloud sync protocol.

TorrentLens is an independent project. It does not require, ship with, or depend
on any publisher's backend, and it operates fully offline.

## Stack (and why)

| Layer | Choice | Notes |
|---|---|---|
| UI, app logic, domain, data, integrations | **Flutter / Dart** | Android is the only shipping target; the layout is mobile-first (bottom navigation, touch-first readers/player). |
| Native services (torrent engine, foreground service, notifications) | **Kotlin** | Reached over a `MethodChannel`. |
| BitTorrent engine | **libtorrent4j 2.1.0-39** | MIT bindings to libtorrent-rasterbar (BSD-3). Ships a prebuilt `libtorrent4j.so`. |
| Local persistence | **SQLite (sqflite)** | Versioned, additive migrations. |
| Secrets | **flutter_secure_storage** | Android Keystore-backed; never written to the database. |
| State / DI | **Riverpod 3** | |
| Navigation | **go_router** | |
| Media playback | **video_player** (Media3/ExoPlayer) | |
| PDF | **pdfrx** (PDFium) | |
| HTML sandbox | **webview_flutter** | JavaScript off by default. |

`libtorrent4j` requires API 28, which pins the app's `minSdk` to **28**.

DRM is deliberately a hard boundary: `DrmCapabilityDetector` only *recognises*
protection, and all provider-authorised playback goes through
`AuthorizedPlaybackAdapter`. Its default implementation fails closed, so the app
never implies that protected content will play.

## Repository layout

```text
lib/
  app/            dependency container (AppServices) + Riverpod providers
  core/           Result type
  design_system/  Material 3 theme + shared state views
  domain/         pure Dart: torrent, tabs, github, security, manifests, media, sync, cloud
  data/           SQLite database + migrations + repositories + secure store
  integrations/   torrent (channel), github, manifests, cloud_providers,
                  media_resolver, reader, web_sandbox, net
  features/       browser (tab workspace), home, downloads, explorer, library,
                  subscriptions, cloud_sync, settings, reader, player,
                  media_resolver, web_sandbox
  navigation/     shell + GoRouter routes
android/app/src/main/kotlin/dev/torrentlens/torrentlens/
  torrent/        LibtorrentEngine, TorrentEnginePlugin (MethodChannel), sanitizer,
                  StreamingSupport (piece deadlines + stream snapshots)
  service/        TorrentDownloadService (foreground), Notifications
test/             235 unit tests (domain, integrations, data, readers,
                  streaming session, tab workspace, update worker)
docs/             architecture, security, source-manifest, cloud protocol,
                  media support, permissions, testing, troubleshooting, status
native-legacy/    the earlier native-only (Kotlin/Compose) prototype, kept for
                  reference; superseded by this Flutter implementation
```

## Build

Requirements: **Flutter stable (3.47.x)**, **JDK 17**, and an **Android SDK with
platform 37 + build-tools**. `minSdk` is 28 and `compileSdk` is 37.

```bash
export JAVA_HOME="$HOME/toolchain/jdk17"
export ANDROID_HOME="$HOME/android-sdk"

scripts/build-apk.sh              # pub get + analyze + test + build (arm64)
scripts/build-apk.sh --all        # every ABI
SKIP_TESTS=1 scripts/build-apk.sh # skip the test run

# or by hand:
flutter pub get
flutter analyze                   # "No issues found!"
flutter test                      # 181 tests, no device required
flutter build apk --debug --target-platform android-arm64
# -> build/app/outputs/flutter-apk/app-debug.apk
```

Device integration tests (Android only):

```bash
flutter test integration_test/app_test.dart -d <device-id>
```

The build is tuned for a small memory budget in `android/gradle.properties`
(one small Gradle JVM, in-process Kotlin compilation). Raise it on a normal
workstation if you like.

## Permissions

`INTERNET`, `ACCESS_NETWORK_STATE`, `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`.

**No storage permissions.** User-chosen files come from the Storage Access
Framework; downloads default to the app's own external files directory.

## Status

See **[docs/status.md](docs/status.md)** for an item-by-item, honest account of
what is implemented, what is verified, and what is *not*.

Headline: the app **builds a real, debug-signed arm64 APK** containing the
`libtorrent4j` native library, and 181 unit tests pass. Everything that needs a
physical device (installation, a real transfer, background behaviour,
on-device rendering) is **not verified here** — this environment has no Android
device or emulator. Nothing in this repository claims otherwise.

## Scope

A general-purpose torrent client and file viewer for legitimate use: open-source
distribution, personal files, authorised content and public-domain works. It
implements no mechanism to evade copyright enforcement, and it does not bypass
DRM or access controls.
