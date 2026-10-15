# Publisher manifest — schema v1

A publisher manifest is a JSON asset attached to a GitHub release. It is the
*only* way content is associated with a publisher; nothing is inferred from a
file name. `ManifestValidator` parses it strictly and **rejects** unknown major
schema versions, unknown capabilities, and insecure cloud endpoints.

## Discovery

`ManifestDiscovery` looks for an asset whose name equals or ends with one of:

```
.manifest.json
torrentlens.manifest.json
source.manifest.json
manifest.json
```

The release itself must not be a draft or a pre-release to be considered by
`newestWithManifest`. If no release publishes a manifest, the app reports
"no manifest asset found" — it does not guess.

## Example

```json
{
  "schemaVersion": 1,
  "publisherId": "example-publisher",
  "sourceId": "comic-x",
  "name": "Example Comic",
  "description": "A public-domain comic collection.",
  "contentVersion": "1.2.0",
  "publishedAt": "2026-02-01T00:00:00Z",
  "releaseUrl": "https://github.com/owner/repo/releases/tag/v1.2.0",
  "magnetUri": "magnet:?xt=urn:btih:<40-hex>",
  "files": [
    { "path": "comic/vol1.cbz", "sizeBytes": 12345678, "sha256": "<64-hex>" }
  ],
  "capabilities": ["torrent", "reader", "reading_progress"],
  "compatibility": { "minAppVersion": "1.0.0", "platforms": ["android"] },
  "updatePolicy": { "checkIntervalHours": 24, "autoDownload": false },
  "cloud": {
    "providerType": "supabase",
    "endpoint": "https://project.supabase.co",
    "protocolVersion": 1,
    "schemaVersion": 1,
    "capabilities": ["reading_progress", "bookmarks"],
    "authMethod": "supabase_anon",
    "scopes": ["reading_progress"]
  },
  "signature": "<base64 Ed25519 signature>",
  "signingKeyId": "release-2026"
}
```

## Field rules

| Field | Requirement |
|---|---|
| `schemaVersion` | Must equal 1. Higher major versions are rejected. |
| `publisherId`, `sourceId` | 2–128 chars, `[A-Za-z0-9][A-Za-z0-9._-]*`. |
| `contentVersion` | Strict SemVer (a leading `v` is tolerated). |
| `publishedAt` | ISO-8601. |
| `releaseUrl` | Absolute `https`/`http`, no credentials, not a private host. |
| `magnetUri` / `torrentUrl` | At least one is required. |
| `files[].path` | Relative; no absolute paths, no `..`. |
| `files[].sha256` | 64 hex characters when present. |
| `capabilities` | Only from the supported set (see below). Unknown → rejected. |
| `signature` | If present, `signingKeyId` is required. |
| `cloud.endpoint` | **`https` only**, public host, no credentials. |
| `cloud.providerType` | `supabase`, `firebase`, `rest`. |
| `cloud.authMethod` | `none`, `supabase_anon`, `firebase`, `bearer_oauth`. |

Supported capabilities: `torrent`, `library`, `reader`, `player`, `bookmarks`,
`reading_progress`, `playback_position`, `subscriptions`, `cloud_sync`, `notes`.

A manifest can never request a new permission, download an executable, or change
application behaviour outside this list.

## Trust

The signature is verified over the manifest minus `signature`/`signingKeyId`
(canonical JSON). See [security.md](security.md). The UI shows the resulting
`TrustStatus` for every subscription and refuses unattended installs unless the
signature is `verified` **and** the manifest opted into `autoDownload`.

## Version comparison

`SemanticVersion` implements SemVer 2.0.0 precedence (prereleases sort below
releases; numeric identifiers sort below alphanumeric). `UpdateEvaluator` returns
one of: `upToDate`, `updateAvailable`, `updateAvailableUntrusted`, `downgrade`,
`invalidVersions`.
