# TorrentLens

An Android-first, general-purpose BitTorrent client with a built-in reader
(EPUB, PDF, CBZ, CBR, images, text) and GitHub release subscriptions with
signature-verified updates.

## Status

| Area | State |
|---|---|
| Domain rules (parsing, semver, integrity, Ed25519, path safety) | **Implemented and unit-tested** — 72 tests green |
| Room persistence layer | **Implemented; compiles and assembles** |
| GitHub client + verified update checker | **Implemented; compiles and assembles** |
| libtorrent4j engine binding + foreground service | **Implemented; compiles; native `.so` packaged in the APK** |
| Reader (EPUB container/OPF, PDF, CBZ, CBR, text, isolated HTML) | **Implemented; compiles and assembles** |
| Compose UI (all required screens + state views) | **Implemented; compiles; APK produced** |
| Debug APK | **Builds** — `app/build/outputs/apk/debug/app-debug.apk` (85 MB, arm64-v8a) |
| Device verification (install, transfer, background, readers) | **Not done — requires a real Android device** |

## Build

```bash
# One-time toolchain bootstrap (no root; installs into $HOME)
./tools/setup-toolchain.sh

export JAVA_HOME="$HOME/toolchain/jdk17"
export ANDROID_HOME="$HOME/android-sdk"

./gradlew :core:domain:test        # pure-JVM rules, 63 tests
./gradlew :core:reader:testDebugUnitTest
./gradlew :app:assembleDebug       # produces app/build/outputs/apk/debug/app-debug.apk
```

`local.properties` holds `sdk.dir` and is gitignored.

### Toolchain actually used

Gradle 9.8.1 · AGP 9.4.1 (built-in Kotlin, so `org.jetbrains.kotlin.android` is
*not* applied) · KGP/KSP 2.2.10 / 2.2.10-2.0.2 (AGP 9's tested pair — there is no
KSP release for Kotlin 2.4.x) · `compileSdk 37` (required by OkHttp 5.5.0) ·
`minSdk 28` (required by libtorrent4j) · `targetSdk 36`.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and the decision records in
[docs/adr/](docs/adr/).

## Permissions

`INTERNET`, `ACCESS_NETWORK_STATE`, `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`.

`READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE` and `MANAGE_EXTERNAL_STORAGE`
are **not** requested. User-chosen files and folders come from the Storage Access
Framework. (`WAKE_LOCK` appears in the built manifest because WorkManager
declares it transitively.)

## Scope

A genuine general-purpose torrent client and file viewer for legitimate use —
open-source distribution, personal files, authorised content and public-domain
works. It implements no mechanism to evade copyright enforcement or to conceal
unlawful distribution.
