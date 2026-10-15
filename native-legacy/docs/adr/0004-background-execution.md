# ADR 0004 — Background execution and battery honesty

- **Status:** Accepted
- **Date:** 2026-10-13

## Decision
Two distinct mechanisms, chosen by the nature of the work:

1. **Active, user-initiated transfers → a foreground service**
   (`TorrentDownloadService`, declared `foregroundServiceType="dataSync"`, with
   `FOREGROUND_SERVICE_DATA_SYNC`). The persistent notification shows real
   progress, speed, peer count and a Pause/Resume action, and is the only thing
   keeping the transfer alive.
2. **Deferrable, periodic work → WorkManager**
   (`ManifestCheckWorker`) for scheduled GitHub release checks, which are
   tolerant of delay and should run inside a maintenance window.

## Explicit non-claims
TorrentLens does **not** claim a download continues forever. Android may stop
transfer work when the user force-stops the app, on aggressive OEM battery
managers, when data-sync time limits expire, or when the device is in Doze with
no active foreground service. The UI states this plainly rather than promising
uninterrupted background downloading.

## Recovery
- Task state (info-hash, progress, file selection, destination, per-task
  settings) is persisted in Room on every state change.
- On process restart the engine re-adds incomplete tasks from their magnet or
  saved `.torrent` metadata and re-checks existing data, so completed pieces are
  not re-downloaded.
- `RECEIVE_BOOT_COMPLETED` re-arms *scheduled manifest checks* only. Transfers are
  **not** silently resumed after reboot unless the user opted in.
