# ADR 0005 — Security model for untrusted input

- **Status:** Accepted
- **Date:** 2026-10-13

Everything downloaded, pasted or subscribed to is treated as hostile.

| Threat | Control | Where |
|---|---|---|
| Hostile torrent file list escaping the download dir | `TorrentFileListSanitizer` + `SafePaths.resolveInside`; reject absolute, `..`, drive/UNC prefixes, NUL bytes, over-long names, duplicates | `:core:domain` (tested) |
| Zip-slip in EPUB/CBZ/CBR/site bundles | Same `SafePaths` rules on every archive entry; post-extraction `isContainedBy` re-check defeats symlink redirection | `:core:domain`, `:core:reader` |
| Tampered release manifest / payload | SHA-256 integrity over the exact artifact bytes and a detached **Ed25519** signature, verified against a **pinned trust root** that the manifest cannot supply | `:core:domain` (tested), `:core:github` |
| Malicious pasted links | Strict parsing of magnets/URLs/repo refs; unsupported schemes (`javascript:`, `data:`, `intent:`) rejected before anything acts on them | `:core:domain` (tested) |
| Downloaded HTML reaching privileged APIs | Site previews render in an isolated `WebView` with `allowFileAccess=false`, `allowContentAccess=false`, `allowFileAccessFromFileURLs=false`, `allowUniversalAccessFromFileURLs=false`, JavaScript off by default, and no `addJavascriptInterface` bridge | `:core:reader` |
| Secrets/keys | Signing keys live in Android Keystore; publisher public keys are compiled-in constants; nothing secret is logged or placed in browser storage | `:app` |

Verification is deliberately **independent of the content it verifies**: the
trust anchor is local, so a compromised release cannot re-sign itself into
acceptance.

## Scope statement
TorrentLens is a general-purpose torrent client and file viewer for legitimate
use — open-source distribution, personal files, authorised content and
public-domain works. It implements no mechanism to evade copyright enforcement
or to conceal unlawful distribution.
