# Implementation status

Honest, item-by-item account. "Verified" means it was actually executed in this
environment and the command/output is reproducible. "Unverified (device)" means
it depends on a real Android device, which this environment does not have.

## Verification actually performed here

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found!** |
| Unit tests | `flutter test` | **181 passed, 0 failed** |
| Debug APK | `flutter build apk --debug --target-platform android-arm64` | **Built**, 169 MB |
| Native engine packaged | `unzip -l app-debug.apk` | `lib/arm64-v8a/libtorrent4j.so` = 15.8 MB |
| Engine Java classes | `strings classes22.dex` | 742 `org/libtorrent4j` refs |
| Kotlin plugin/service | dex scan | `TorrentEnginePlugin`, `TorrentDownloadService` present |
| PDF + SQLite native | `unzip -l` | `libpdfium.so`, `libsqlite3.so` present |
| Permissions | `aapt2 dump badging` | No storage permission |
| minSdk | `aapt2 dump badging` | 28 (required by libtorrent4j) |

Test breakdown: domain (torrent, github, security, signatures, manifest, media,
sync, update evaluator) + integrations (media resolver, github, cloud) + data
(real SQLite via FFI) + readers.

## Definition of Done

| # | Criterion | State | Notes |
|---|---|---|---|
| 1 | A real Android APK builds and installs | **Builds (verified). Installs (unverified)** | APK inspected. Installation needs a device. |
| 2 | Coherent, functional mobile UI | **Implemented (verified by analysis/tests, not by touch)** | 6 destinations, import sheet, reader/player screens. Runtime behaviour unverified. |
| 3 | Magnet URIs and torrent files importable | **Implemented** | `MagnetUri` parsing (hex + base32, v1 only, v2 rejected) is unit-tested; `.torrent` via SAF. End-to-end unverified. |
| 4 | Genuine BitTorrent engine performs real downloads | **Engine integrated (verified). Real transfer (unverified)** | libtorrent4j session/DHT/peers; the native lib is in the APK. No peer network tested here. |
| 5 | Background transfers and recovery | **Implemented (unverified)** | Foreground service + WorkManager + DB reconciliation. Needs device/Doze testing. |
| 6 | Browse content and open supported files | **Implemented** | Explorer with filters, sorting, search, open-with routing. |
| 7 | EPUB, PDF, comic/image viewers work | **Implemented (PDF via PDFium; EPUB is text-based)** | CBR/RAR **not supported** (no maintained Dart decoder) — stated in the UI. |
| 8 | Local media plays in built-in player | **Implemented** | video_player/Media3, resume, speed, SRT/WebVTT subtitles, and play-while-downloading from a torrent. Audio-track selection & PiP not implemented. |
| 9 | Embedded media and torrent links discovered and routed | **Implemented** | Static extraction from HTML/CSS; no script execution; explicit resource panel. |
| 10 | Untrusted HTML isolated | **Implemented** | JS off by default, no JS channels, navigation re-validated, external links handed to OS. |
| 11 | DRM capabilities and limits transparent | **Implemented** | `DrmCapabilityDetector` recognises protection; `AuthorizedPlaybackAdapter` is the only playback route and its default fails closed (`providerNotConfigured`). **No circumvention.** |
| 12 | GitHub subscriptions detect updates | **Implemented (API client unit-tested)** | Release parsing, rate-limit handling, semver comparison. Live check unverified. |
| 13 | Manifests validated, trust status visible | **Implemented and unit-tested** | Strict schema; Ed25519; trust states surfaced in UI. |
| 14 | Optional publisher-owned cloud sync via documented protocol | **Implemented (mock + REST)** | Firebase adapter not implemented. Protocol documented. |
| 15 | App useful without cloud sync | **Yes** | Local-first; sync is opt-in. |
| 16 | No secrets in APK or logs | **Verified by construction** | Secrets only in Keystore-backed storage; no key in assets or source. |
| 17 | Critical workflows pass automated tests | **Partially** | 181 unit tests pass, including 42 covering the streaming window/buffer maths and session state machine. Two device integration tests exist (`integration_test/app_test.dart`) but have **not been run** — no device. |
| 18 | Background execution and recovery verified on a real device | **NOT DONE** | No device/emulator here. |
| 19 | Documentation | **Done** | `docs/` covers architecture, security, manifest, cloud protocol, media, permissions, testing, troubleshooting. |

## Known gaps (not hidden, not faked)

1. **EPUB rendering is text-based.** Container/OPF/spine/nav parsing is real and
   tested; chapters render as paginated text. In-book images and CSS are not
   rendered yet.
2. **CBR/RAR comics unsupported.** No maintained permissive pure-Dart RAR
   decoder. The app says so rather than failing silently.
3. **`kPinnedPublisherKeys` is empty.** Every signature therefore reports as
   `unknownPublisher` — fail-closed. The user must add their release key.
4. **Firebase cloud adapter is a stub** in the factory; Supabase/self-hosted REST
   and the mock provider are real.
5. **Player gaps:** no audio-track selection, no Picture-in-Picture, no
   background audio.
6. **Play-while-downloading is implemented but never observed on hardware.** The
   piece-window arithmetic, buffer depth, stall detection and the whole session
   state machine are unit-tested against a fake engine, but the native priority
   calls, delivery from real peers while playing, and ExoPlayer behaviour on a
   sparse partial file have not been seen on a device. Known design limits:
   one streaming window per torrent at a time; the position → byte mapping
   assumes roughly constant bitrate; and the anti-starvation recovery (which
   prioritises the file tail for an MP4 `moov`) gives up after 5 attempts.
7. **Most integration tests are not written.** `integration_test/app_test.dart`
   covers boot + platform-channel reachability but has not been executed here.
   The remaining flows needing coverage are listed in testing.md.
8. **Torrent engine native lib ships for arm64 only** in the arm64 build; the
   debug APK also includes armeabi-v7a and x86_64 Flutter runtimes but the engine
   `.so` is arm64.

## What to do next (on a real device)

1. `flutter build apk --debug --target-platform android-arm64`, install on an
   arm64 phone (Android 9+).
2. Add a magnet for a controlled, legal test torrent; confirm metadata resolves
   and a real transfer completes. Watch the notification.
3. Pause, resume, kill the app, relaunch: confirm recovery.
4. Open an EPUB, a PDF, a CBZ and a video; note anything broken. Then start a
   video download and open it from Downloads while it is still running: check that
   the buffering readout is plausible, that seeking resumes instead of failing,
   and that a completed file stops needing peers.
5. Subscribe to a GitHub repo that publishes a manifest; add a key to
   `kPinnedPublisherKeys` and confirm the trust state flips to `verified`.
6. Record device + Android version and any failures. Report them; do not assume
   the criteria are met until then.
