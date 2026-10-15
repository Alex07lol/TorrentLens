# ADR 0003 — Reading stack for EPUB, PDF, CBZ, CBR, text and site bundles

- **Status:** Accepted
- **Date:** 2026-10-13

## Decision, per format

| Format | Approach | Licence |
|---|---|---|
| **EPUB 2/3** | Readium Kotlin toolkit (`org.readium.kotlin-toolkit:readium-shared/streamer/navigator` 3.4.0). Host the established `EpubNavigatorFragment` behind a Compose `AndroidView`; Readium's Compose web renditions are still experimental. | BSD-3 |
| **PDF** | Platform `android.graphics.pdf.PdfRenderer` into a Compose pager (per-page bitmaps, bounded LRU cache, pinch-zoom). Avoids a dead upstream (barteksc/AndroidPdfViewerV2 is stale and JCenter-era). | Platform API |
| **CBZ** | JDK `ZipFile` entry listing + a page-ordered Compose pager, images loaded with Coil 3. | Platform / Apache-2.0 |
| **CBR** | `com.github.junrar:junrar` — **flagged as opt-in and licence-reviewed**: junrar is under the **UnRAR licence**, which permits extraction but is not a standard permissive OSS licence. It ships only where distribution policy allows, and the app degrades gracefully (CBR simply not listed as supported) when absent. | **UnRAR (restrictive)** |
| **Images** | Coil 3 (`io.coil-kt.coil3:coil-compose` 3.6.3). | Apache-2.0 |
| **Plain text** | Chunked read + paginated Compose layout; never load a whole large file as one UI string. | — |
| **Static site bundles** | Rendered in an isolated `WebView`, see ADR 0005. | — |

## Consequences
- Readium requires its own initialization and a Fragment host; this leaks into
  the reader module but is contained there.
- The CBR licence is the one non-permissive dependency. It is isolated in
  `:core:reader` and documented for distribution review.
- RTL manga mode, page/scroll modes, bookmarks and progress are our UI concerns
  layered on top of these engines, not provided by them.

## Implementation status (2026-10-13)

Staged deliberately, and the code reflects the staging honestly:

- **Shipped now:** the EPUB *structure* layer (`META-INF/container.xml` → OPF →
  manifest + spine, with `ArchivePath` resolving hrefs and refusing to escape the
  archive), an XXE-hardened XML parser, and chapter rendering into the isolated
  `WebView` with reader-controlled typography, theme and RTL direction.
- **Shipped now:** PDF via `android.graphics.pdf.PdfRenderer` (one page rendered
  at a time, bounded memory), CBZ via `ZipFile`, CBR via junrar, plain text via
  chunked pagination, images via `BitmapFactory` downsampling.
- **Not yet wired:** Readium's navigator for CSS/Readium-CSS-quality reflowable
  typography, in-archive resource resolution (images/CSS referenced by relative
  path inside an EPUB are not yet inlined, so chapters currently render as
  styled text), fixed-layout EPUB, and EPUB 3 media overlays.

Readium remains the chosen rendering engine for the presentation layer. Because
the spine-discovery contract is already ours, adopting it changes how a resolved
href is displayed and nothing else.
