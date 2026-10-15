# Media support

## Readers

| Format | Support | Notes |
|---|---|---|
| EPUB | **Yes** — own parser | OCF container → OPF → spine, nav/NCX titles, text extraction. Chapters are rendered as paginated text; in-chapter CSS and in-book images are **not** rendered yet. |
| PDF | **Yes** | `pdfrx`/PDFium, scrolling + zoom, page navigation, resume, error reporting. |
| CBZ | **Yes** | Pages are listed in natural order (`page2` before `page10`), lazy per-page reads. |
| CBR / RAR | **No** | There is no maintained permissively-licensed pure-Dart RAR decoder. The app says so, and suggests converting to CBZ. |
| Images | **Yes** | JPG/PNG/GIF/WebP/BMP/AVIF/JXL by extension. |
| Text | **Yes** | Stable pagination, font sizing, resume. |
| Markdown | **Partial** | Rendered as text; a rich Markdown renderer is not wired up yet. |
| HTML bundles | **Yes** | Sandboxed WebView (see below). |

Resume positions are stored per content id and restored on open.

## Player

Built on `video_player` (Media3/ExoPlayer on Android).

| Capability | State |
|---|---|
| Local video/audio | Yes |
| Remote `http(s)` media | Yes |
| HLS / DASH | Yes (the classifier detects them; ExoPlayer plays them) |
| Resume position | Yes |
| Playback speed | Yes |
| External SRT / WebVTT subtitles | **Yes** — parsed by `SubtitleTrack` and rendered as an overlay |
| Audio-track selection | **No** — not exposed by the plugin used here; reported instead of faked |
| Picture-in-Picture | **Not implemented** |
| Background audio | **Not implemented** |
| Torrent-backed progressive playback | **Yes** — play while downloading (see below) |

Failures are explained by `PlaybackDiagnostics`: network, HTTP status,
unsupported container/codec, DRM unauthorised/unsupported, invalid manifest,
decode error — never a bare "cannot play".

## Play while downloading (torrent-backed playback)

Reached from **Downloads → the play icon** on a task, which lists its audio and
video files and opens the player in streaming mode. The player reads the local
*partial* file directly; the torrent engine is told which pieces the playhead
needs.

How the window is chosen:

- `StreamingPolicy` (pure Dart, unit-tested) turns a playback position into an
  absolute piece range: a 24 MiB read-ahead from the playhead, clamped to the
  file's own piece range and to 512 pieces per request.
- `LibtorrentEngine.beginStreaming` raises the streamed file and those pieces to
  `Priority.TOP_PRIORITY` and sets **graded piece deadlines** — 1.5 s for the
  piece under the playhead, +250 ms per piece of distance — so the window
  arrives in playback order instead of racing.
- The file's previous priority is remembered and restored when playback ends, so
  streaming never silently changes the user's file selection. Changing the
  selection *during* playback re-applies the window and updates what will be
  restored.

Buffering feedback is measured, not guessed. The engine reports which pieces of
that range are verified on disk; the app converts the *unbroken run* from the
window start into bytes (`contiguousBytes`, with the part of the first piece
behind the playhead subtracted) and compares it with the required depth — a
quarter of the read-ahead, floored at 4 MiB, never more than the file has left.
The overlay shows buffered vs. needed bytes, download speed, peer count and the
file's overall progress. If the buffer stops growing for 10 s the session says
**stalled** and names the peer count and speed, rather than showing a spinner
forever.

Behaviour worth knowing:

- Playback starts only once the required depth is contiguous. A seek past half a
  window re-aims the pieces at the destination; a small seek needs no change
  because the data is already prioritised.
- If the player reads past the downloaded region it is stopped and treated as an
  empty buffer, then resumed at the same position once data arrives. The first
  such attempt also prioritises the last 4 MiB of the file, where MP4 `moov`
  indexes normally live. After 5 attempts the player gives up with an explicit
  message instead of looping.
- The position → byte mapping assumes a roughly constant bitrate. Variable
  bitrate media is positioned approximately; the buffer is re-measured from
  whatever window that produces.
- One streaming window per torrent at a time, and the native engine ships for
  **arm64 only**, like the rest of the torrent stack.
- **Unverified on a device.** No Android device or emulator is available in the
  development environment, so the native priority calls, real peer delivery while
  playing, and ExoPlayer behaviour on a sparse partial file have not been
  observed on hardware. What *is* verified: the window/buffer arithmetic and the
  whole session state machine, against a fake engine (42 tests).

## Media Link Resolver

Discovers and classifies links from HTML, CSS and (statically) script text.
It never executes scripts to find links, never downloads discovered resources
automatically, and every resource is shown in a panel with its detected type,
source page and the action that will be taken.

Routing:

| Detected | Action |
|---|---|
| Video / audio | Built-in player |
| HLS / DASH | Built-in player with the manifest |
| Subtitle | Attach to the current playback session |
| Image | Image/comic viewer |
| EPUB / PDF / comic archive | Corresponding reader (confirmation required) |
| Magnet | Add-torrent flow (confirmation required) |
| `.torrent` | Inspect then add (confirmation required) |
| HTML bundle / page | Sandboxed viewer (confirmation required) |
| DRM-protected | DRM explanation flow |
| Unsupported | Explanation with safe alternatives |

## DRM

`DrmCapabilityDetector` recognises Widevine, PlayReady, ClearKey and FairPlay
UUIDs, plus `mp4protection` descriptors and DRM response headers, and reports
whether the device stack *could* play the stream **if** the provider authorises
it. Recognition is never support.

All provider-authorised playback goes through `AuthorizedPlaybackAdapter`.
The app ships `UnconfiguredAuthorizedPlaybackAdapter`, which returns
`providerNotConfigured` — the honest, fail-closed default. Only when an adapter
returns `authorized` does `canPlay` become true. `DrmAuthorizationResult`
distinguishes refusal from an unreachable license server, an expired
entitlement, and an unsupported protection system; `DrmPlaybackRequest.describe`
is token-free so nothing sensitive can reach a log.

TorrentLens does **not** perform license acquisition, does not extract or
manipulate keys, and does not bypass protection. When playback cannot be
authorised it offers to open the source in its official app or browser.
