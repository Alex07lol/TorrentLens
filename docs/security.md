# Security model

## Threat model

| Asset | Threat | Control |
|---|---|---|
| The user's other files | A hostile torrent escapes the download directory | `TorrentFileListSanitizer` (Kotlin) + `ArchiveSafety` (Dart) reject absolute paths, `..`, drive letters, backslashes, NUL bytes, duplicates |
| The device's memory | A decompression bomb, or a giant response | Entry/total size caps, compression-ratio heuristic, streaming byte caps on every HTTP read (`maxBytes`) |
| The user's credentials | Secrets leaking into the DB, logs or assets | `flutter_secure_storage` (Android Keystore) only; no secret is ever written to SQLite or logged |
| The user's identity | A malicious page fetching internal endpoints | `UrlPolicy` blocks non-http(s) schemes, private/loopback hosts and credential-bearing URLs; `RedirectResolver` validates **every** hop |
| Update integrity | A tampered or impersonated release | Ed25519 verification over a canonical JSON payload, fail-closed on unknown/revoked keys |
| The app process | Untrusted HTML reaching app APIs | `WebSandboxPolicy`: JavaScript off by default, **no** JavaScript channels registered, navigation re-validated, external links handed to the OS browser |

## Trust states

`TrustStatus` (see `lib/domain/security/signatures.dart`) is surfaced verbatim in
the UI:

```
unsigned · unknownPublisher · keyRevoked · verified · invalidSignature · integrityFailed
```

Only `verified` is trusted. A checksum proves the bytes did not change; it does
**not** prove who published them, so a manifest with a hash but no valid
signature is never treated as trusted and is never auto-installed.

## Key distribution

`kPinnedPublisherKeys` in `lib/domain/security/trusted_keys.dart` is the pinned
registry. It is **empty by default**, which makes every signed manifest report
as `unknownPublisher` — the fail-closed behaviour. Populate it with your real
release key before distributing an app that consumes your manifests.

Rotation and revocation are expressed in the data model: a `TrustedKey` carries
its `keyId` and a `revoked` flag, and a revoked key produces a distinct,
user-visible status rather than a generic "invalid".

## Signing payload

The signature covers the manifest with `signature`/`signingKeyId` removed,
serialised deterministically (object keys sorted, no insignificant whitespace).
Altering *any* field invalidates the signature — including the content version.
This is covered by tests (`test/domain/signatures_test.dart`,
`test/integrations/github_test.dart`).

## What TorrentLens does **not** do

- It does not implement DRM cracking, license extraction, or circumvention of
  access controls.
- It does not attempt to hide the user's network identity, and it says so:
  ordinary BitTorrent connections expose the IP to peers and trackers.
- It does not execute downloaded binaries, scripts, or plugins from manifests.
