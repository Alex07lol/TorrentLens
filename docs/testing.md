# Testing

## Unit tests (no device required)

```bash
flutter analyze     # expected: "No issues found!"
flutter test        # expected: 181 tests, all passing
```

| Area | File | What is checked |
|---|---|---|
| Magnet/info-hash | `test/domain/torrent_test.dart` | hex + base32 vectors, distinct errors, v2 rejection, duplicate handling |
| Task state machine | `test/domain/torrent_test.dart` | legal/illegal transitions |
| GitHub refs, SemVer | `test/domain/github_test.dart` | URL forms, reserved owners, precedence rules |
| URL policy | `test/domain/security_test.dart` | scheme allow-list, SSRF/private hosts, credentials, redirect validation |
| Integrity | `test/domain/security_test.dart` | NIST SHA-256 vectors, constant-time compare |
| Archive safety | `test/domain/security_test.dart` | zip-slip, absolute paths, drive letters, bombs |
| Ed25519 | `test/domain/signatures_test.dart` | genuine / tampered / unknown key / revoked key / unsigned |
| Manifest schema | `test/domain/manifest_validator_test.dart` | strict parsing, capability allow-list, insecure cloud endpoints |
| Media classification | `test/domain/media_test.dart` | MIME over extension, conflicts, magnet/unsafe schemes, DRM |
| Authorised playback | `test/domain/media_test.dart` | default adapter fails closed; only `authorized` sets `canPlay`; distinct refusal outcomes; `describe()` leaks no token |
| HLS/DASH | `test/domain/media_test.dart` | master playlists, EXTINF sums, MPD durations |
| Sync conflicts | `test/domain/sync_test.dart` | version/timestamp/device tie-break determinism, merges |
| Update evaluation | `test/domain/update_evaluator_test.dart` | up-to-date, trusted/untrusted update, downgrade |
| Media resolver | `test/integrations/media_resolver_test.dart` | extraction, redirect policy, no eager fetching, routing |
| GitHub + updates | `test/integrations/github_test.dart` | release parsing, rate limits, signed update end-to-end |
| Cloud sync | `test/integrations/cloud_sync_test.dart` | push/pull, idempotency, merges, 409 conflicts, malformed records |
| Database | `test/data/database_test.dart` | migrations, all tables, FK cascade, repositories, persistence across reopen |
| Readers | `test/readers/readers_test.dart` | EPUB spine/titles/resources, zip-slip, CBZ ordering, pagination, SRT/VTT |
| Streaming maths | `test/domain/streaming_test.dart` | piece windows (mid-piece playheads, file end, multi-file offsets, 512-piece cap), contiguous-buffer runs and gaps, required depth, phases incl. stall vs. ready, seek/re-window decisions, position → byte mapping |
| Streaming session | `test/features/streaming_session_test.dart` | window applied to the engine, ready/stalled/failed transitions, buffer target following the playhead, tail prioritisation, refusals when data is missing, release on end/dispose, polling stops |

SQLite tests run against the real SQLite library on the Dart VM via
`sqflite_common_ffi`. Streaming session tests run against
`test/support/fake_torrent_engine.dart`, which reports a fixed set of downloaded
pieces — enough to exercise the whole decision path without a peer network. The
native library itself is **not** exercised by any test here; that needs a device
(see below).

## Integration tests (need a device)

`integration_test/app_test.dart` runs on Android and exercises the real platform
channel — no mocks:

```bash
flutter test integration_test/app_test.dart -d <device-id>
```

| Test | What it proves |
|---|---|
| app boots into the navigation shell | `AppServices.open()` (SQLite + secure store on device) works and the shell renders a `NavigationBar`. |
| native engine reachable over the channel | The Kotlin plugin answers; `start` makes `isRunning` true and `stop` makes it false; a fresh session reports an empty status list. |

These do **not** prove a real transfer. The remaining flows still need coverage:
add a magnet, pause/resume, restart recovery, open EPUB/PDF/comic, play media,
resolve embedded links, subscribe and detect an update, and sync against the mock
provider. See [status.md](status.md).

## Real-device verification

**Not performed.** This environment has no Android device or emulator, so the
following are unverified and must be checked on hardware:

installation and first launch · storage permission flows · a real transfer ·
pause/resume and restart recovery · background/Doze behaviour · notifications ·
network changes · reboot · low memory · large files and low disk space ·
playback lifecycle · PiP · database migration across an app upgrade.

Document the device and Android version you actually tested on. Do not report a
device check you did not run.
