# ADR 0001 — Native Android (Kotlin + Jetpack Compose), not a portable shell

- **Status:** Accepted
- **Date:** 2026-10-13

## Context
TorrentLens must be Android-first and must be reliable on real phones: sustained
background transfers, scoped storage, process death, Doze/App Standby, and
touch-first reading. A cross-platform shell (Tauri/Electron-style, or a
desktop-first UI toolkit) would reuse one UI layer but would push the hardest
Android work — lifecycle, foreground services, SAF, battery — into plugin
boundaries we would still have to write and debug on-device.

## Decision
Android is implemented natively: **Kotlin + Jetpack Compose + AndroidX**. The
BitTorrent engine is consumed through a Kotlin interface, not through a webview
bridge. Shared, platform-free rules (link/manifest parsing, version comparison,
integrity and signature verification, path safety) live in the pure-JVM
`:core:domain` module so they can be reused by future Windows/Linux clients
without a rewrite.

## Consequences
- Best available control over battery, lifecycle, storage and notifications.
- Desktop ports are a later adapter over `:core:domain`, and must not delay Android.
- No single-UI-language reuse; accepted deliberately.
