# ADR 0007 — Persistence and dependency wiring

- **Status:** Accepted
- **Date:** 2026-10-13

## Decision
- **Room** for all persistent metadata: torrent tasks, file selections, library
  items, reading progress and bookmarks, subscriptions, release history and
  settings-oriented rows. Flow-based DAOs so the Compose layer observes changes.
- **DataStore (Preferences)** for small scalar settings (bandwidth caps, theme,
  update-check interval, read RTL).
- **Manual constructor injection via a single `AppContainer`** rather than Hilt.
  The graph is small, and this keeps annotation processors out of the build
  (only Room's KSP processor remains), which materially shortens build times in
  a constrained environment and removes a whole class of configuration risk.

## Consequences
- `AppContainer` is created in `Application.onCreate` and exposed to
  ViewModels through a small factory — explicit, testable, and easy to migrate to
  Hilt later if the graph grows.
