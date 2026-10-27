# Office startup: WebKit downloads and Brotli

The preceding optimization used `<link rel="preload" as="fetch">` for the app
and renderer. Chrome reused those responses, but the tested WebKit browser
requested both files again when the host called `fetch`. The launcher now
passes the actual response promises to the host. Standalone Office pages do
the same for their app, renderer and font manifest. Downloads still begin only
when a product-page visitor opens an editor.

The app also has a Brotli representation: 5,330,597 bytes versus the retained
7,386,914-byte gzip file. Selection uses the actual native decoder, not a user
agent check. Browsers without native Brotli decoding use gzip directly. An
unavailable or corrupt Brotli response falls back to gzip. There is no added
browser library. WebKit documents its native decoder on Apple platforms in
[Compression Streams](https://docs.webkit.org/Deep%20Dive/Modules/CompressionStreams.html).

Both files decode to the same 21,210,560-byte app, SHA-256
`da539de31bc5d29689a849e120e605251328a4081efe847a00ada3c5c1525d80`.
The Swift app, renderer and fonts are unchanged.

## Measurement

Three fresh desktop WebKit browsers/contexts per version, alternating before
and after; 1440 × 1000 viewport, no CPU throttle. The browser reports Safari
27.2 / WebKit 605.1.15. Both local servers gzip the same eligible assets and
serve the same cache headers. Each server shares a 10 Mbps response-body rate
limit across connections, with 40 ms delay before each response. This is a
server-side network model, not the Chrome CDP emulation used in earlier
reports. The page opens Writer's default welcome document with `?start=new`.

Before: source 4405223a, production package 4b66d86. After: shared responses
and the Brotli app. [Run data](office-web-startup-20261026-webkit.json) retains
startup totals and individual app/renderer requests.

| Median cold-load metric | Before | After |
| --- | ---: | ---: |
| First displayed frame | 16.56 s | 8.28 s |
| Same-origin resource transfers | 20.80 MB | 9.58 MB |
| App requests | 2 × gzip | 1 × Brotli |
| Renderer requests | 2 | 1 |

This is a desktop WebKit result, not an actual iPhone measurement. The two
screenshots were pixel-identical. Chrome, which used the gzip path in this
test environment, still loaded 11.63 MB in 9.34 seconds under the existing
10 Mbps / 40 ms CDP test; its cached first frame was 0.44 seconds. That is a
single regression check, consistent with the previous three-run Chrome result.

## Correctness and failure checks

- Real WebKit tests cover native Brotli, forced lack of decoder support,
  a 404 response and a corrupt Brotli stream, plus standalone Writer.
  Every case reaches the expected document. Only the failure cases request
  both representations; the renderer is requested once. Idle product pages
  request no runtime.
- Chrome opens and saves all three populated Office examples, retaining the
  existing checks for text, tables, images, charts, formulas and presentation
  data. Existing deferred-font tests also pass.
- Four documents exported to 14 PDF pages: all retained their text, page
  dimensions and font types. Thirteen pages rasterized identically at 108 dpi;
  the spreadsheet differed in 36 RGB channels by only one intensity level.
- Configuring a stage twice is stable. Older hosts without the new capability
  still package and open normally, without the new response-sharing path.

## Rejected font experiment

WOFF2 reduced font transfer size and rendered identically on screen, including
Chinese text. However, the current PDF backend fell back from embedded Type0
fonts to Type3 glyph outlines, changing rasterization and font embedding.
That conversion was rejected. No WOFF2 fonts or font-conversion code are part
of this release. Chinese fonts remain deferred TTF files.
