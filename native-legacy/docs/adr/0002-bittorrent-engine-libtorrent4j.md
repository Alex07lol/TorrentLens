# ADR 0002 — BitTorrent engine: libtorrent4j

- **Status:** Accepted (pending on-device validation — Phase 1)
- **Date:** 2026-10-13

## Context
The engine is the highest-risk dependency. It must be maintained, Android-capable,
permissively licensable, and complete enough for DHT, trackers, magnets, uTP,
seeding and upload limits.

Options evaluated against Android support, licence and maintenance:

| Option | Android | Licence | Verdict |
|---|---|---|---|
| **libtorrent4j** (Java/JNI bindings to libtorrent-rasterbar) | Published ABI-specific JARs (arm, arm64, x86, x86\_64); **minSdk 28** | Bindings MIT; libtorrent 3-clause BSD | **Chosen** |
| FrostWire jlibtorrent | All four ABIs, SDK 24+, documents 16 KB page-size compat | MIT bindings | Closest runner-up; separate Maven repo and inconsistent published versions |
| rqbit (Rust) | No official Android AAR | Apache-2.0 | Would require us to own a Rust→Kotlin JNI bridge |
| anacrolix/torrent (Go) | Go mobile is experimental | MPL-2.0 | Not a drop-in Kotlin dependency |

Licence compatibility: libtorrent-rasterbar is permissive (BSD-3), so it is
compatible with both a closed-source and a GPL Android app; we must ship the
upstream notices.

## Decision
Use **`org.libtorrent4j:libtorrent4j:2.1.0-39`** plus the per-ABI native artifacts
from Maven Central (`libtorrent4j-android-arm64`, `-arm`, `-x86`, `-x86_64`).
Mirror the engine behind `TorrentEngine` in `:core:torrent` so it can be swapped
for FrostWire's build without touching the UI or the data layer.

## Consequences
- **minSdk is pinned to 28** (Android 9) by this dependency. This is a product
  decision, not a Gradle preference.
- Release builds ship **`arm64-v8a` only**; the other ABIs exist for emulators
  and local testing.
- Phase 1 must confirm, on a real device: magnet metadata retrieval, DHT
  bootstrap, tracker discovery, uTP vs TCP peers, pause/resume, and sustained
  transfer under Doze. An emulator does not prove this.
