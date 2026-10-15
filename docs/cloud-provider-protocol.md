# Publisher-owned cloud protocol

Cloud sync is **optional**. TorrentLens has no central database and no central
publisher catalogue; a publisher that wants sync runs its own backend and
describes it in its manifest (`cloud` block).

## Models

| Provider | Adapter | Notes |
|---|---|---|
| Supabase | `RestCloudProvider` + `apikey` header | The **anon key** is a public client credential; Row Level Security is the boundary. The service-role key must never ship. |
| Self-hosted REST | `RestCloudProvider` | See the wire format below. |
| Firebase | *not implemented* | The interface is in place (`CloudProviderFactory`); a real adapter needs a verified client SDK and rules. |
| Mock | `MockCloudProvider` | In-memory, registers only when explicitly requested (tests). |

The registry (`CloudProviderRegistries.standard`) refuses an unsupported provider
type rather than falling back to something permissive.

## Wire format (REST)

```text
GET    {endpoint}/{collection}?since=<ISO8601>   -> 200 [ {record}, ... ]
POST   {endpoint}/{collection}                   -> 200 {record} | 409 conflict
DELETE {endpoint}/{collection}/{key}             -> 204
```

Record:

```json
{
  "key": "content-id",
  "type": "reading_positions",
  "payload": { "locator": "ch:3:p:12", "fraction": 0.42 },
  "version": 7,
  "updatedAt": "2026-02-01T12:00:00Z",
  "deviceId": "dev-ab12…"
}
```

Every response is validated against this shape before use; a malformed record is
rejected (`RestCloudProvider.pull` returns an error) instead of being written.

## Conflict resolution

`SyncConflictResolver` is deterministic so that **every device independently
reaches the same answer**:

1. Higher `version` wins.
2. Equal versions → newer `updatedAt` wins.
3. Still equal → the lexicographically smaller `deviceId` wins.

Per-type merges override this where it makes sense: reading progress takes the
maximum fraction, bookmarks take a sorted union.

## Guarantees

- **Additive only.** A failed sync never deletes local data.
- **Idempotent.** Versions are monotonic, so re-running is a no-op.
- **Isolated failures.** A failing collection is recorded in the report; other
  collections still sync.
- **Offline-first.** Writes can be queued (`sync_queue`) and replayed.
- **Disconnect is safe.** Disconnecting removes the saved provider config and the
  queue; the library, progress and bookmarks stay.

Synchronised by default: reading positions and bookmarks. Files, downloads and
browsing history are never uploaded.

## Security

- Provider endpoints must be `https` and must not be a private/loopback host.
- Credentials live in `flutter_secure_storage`, keyed per provider host.
- Responses are validated, never executed.
- The app works fully with no provider configured.
