# ADR 0006 — Storage and permissions

- **Status:** Accepted
- **Date:** 2026-10-13

## Decision
- **SAF everywhere for user-chosen data.** Directories via
  `ACTION_OPEN_DOCUMENT_TREE` and files via `ACTION_OPEN_DOCUMENT`, persisted with
  `takePersistableUriPermission`. Torrents are written through a
  `DocumentFile`-based destination so no broad storage permission is needed.
- **No `MANAGE_EXTERNAL_STORAGE`.** It is not required for the implemented
  features and would jeopardise Play distribution.
- **App-private storage by default** for the Room DB, engine state and the
  extracted-page cache, so nothing sensitive is world-readable.

## Permission set (all requested at the point of use, each with a stated reason)
| Permission | Why |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | Peers, trackers, DHT, GitHub API |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC` | Keep a user-initiated transfer running |
| `POST_NOTIFICATIONS` (API 33+) | Progress and completion notifications |
| `RECEIVE_BOOT_COMPLETED` | Re-arm *scheduled* manifest checks only |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | **Not requested.** Offered as an optional Settings link with an explanation, never demanded |

## Failure handling
Scoped storage, revoked permissions, removable volumes that disappear, and
insufficient disk space are all first-class states with their own UI (permission
denied / stale SAF grant / storage full), not crashes.
