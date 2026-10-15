# Permissions

TorrentLens requests the minimum set required by the features it actually
implements.

| Permission | Why | Requested when |
|---|---|---|
| `INTERNET` | BitTorrent peers/trackers/DHT, GitHub API, publisher endpoints | Install time |
| `ACCESS_NETWORK_STATE` | Distinguish "offline" from "failed" and adapt | Install time |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC` | Keep a **user-initiated** transfer alive with a visible notification | Install time |
| `POST_NOTIFICATIONS` | Transfer progress and "new release" alerts | **Runtime**, on Android 13+, with an explanation in Settings before the prompt |
| `RECEIVE_BOOT_COMPLETED` | Re-arm *scheduled manifest checks* only — transfers never resume silently | Install time |

## Deliberately **not** requested

- `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE`
- `MANAGE_EXTERNAL_STORAGE`

User-chosen files and folders come from the **Storage Access Framework**
(`ACTION_OPEN_DOCUMENT` / `ACTION_OPEN_DOCUMENT_TREE`, via `file_picker`).
Downloads default to the app's own external files directory, which needs no
permission at all.

`VIBRATE`, `WAKE_LOCK` and `FOREGROUND_SERVICE_SHORT_SERVICE` appear in the built
manifest because WorkManager and the notification plugin declare them
transitively.

## Handling failure

- A denied notification permission does not break transfers; the app explains
  what is missing and offers to open system settings.
- Insufficient disk space and revoked access to a user-chosen folder are
  surfaced as errors on the task, not as a crash.
- The app never requests a broader permission to work around a denial.
