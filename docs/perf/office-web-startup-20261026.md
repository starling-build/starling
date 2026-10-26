# Office web startup — 2026-10-26

The product site was downloading the optional Starling FangSong and Archivo
Black fonts before mounting any document. Those files fell through the Office
font classifier and had empty family lists, so the on-demand loader could not
request them. The shared packaging policy now names and defers them. UI,
default-document, and symbol fallback fonts stay eager. The product launcher
also fetches its font manifest alongside the host module and its imports.

This changes web packaging and launch code. The Swift app and rendering engine
are the same binaries from the tested 2f43d5ca deployment. Native font handling
is unchanged. Existing stages get the same font policy as new web builds;
the product runtime hash includes the effective manifest, and standalone
Writer versions its manifest URL.

## Controlled measurement

Three fresh Chrome profiles per version, each followed by a cached reload.
Headless desktop Chrome, 1440 × 1000, software graphics, no CPU throttling.
CDP network emulation: 10 Mbps, 40 ms latency. Both local servers serve gzip
for the same eligible types as the production delivery; the identical Swift
app is already gzipped. Tests open a blank Writer document with `?start=new`.
The before/after runs use the same machine, runtime, and network settings.

| Median metric | Before | After |
| --- | ---: | ---: |
| First frame, cold | 12.90 s | 9.80 s |
| Fonts settled, cold | 13.46 s | 10.35 s |
| Same-origin startup resource transfers | 15.92 MB | 11.97 MB |
| First frame, cached | 0.46 s | 0.44 s |

Approximately 25% fewer startup bytes and 24% less time to first frame in this
bandwidth-limited test. These are not iPhone measurements or promises for every
connection. Cached times are essentially unchanged. Resource transfers exclude
navigation HTML and third-party analytics; full samples and phases are in
[office-web-startup-20261026.json](office-web-startup-20261026.json).

## Correctness checks

- Blank Writer screenshots were pixel-identical before and after.
- A synthetic DOCX requesting Archivo Black and Chinese text in 宋体 fetched
  Archivo Black and Noto Sans SC on demand. Its screenshot and layout dump were
  identical before and after. Unused FangSong was not fetched; explicitly
  requesting `Starling FangSong` still loaded and registered it successfully.
- All three bundled examples opened and saved, passing existing checks for
  document contents, tables, pictures, charts, formulas, and presentation data.
- Standalone Writer opened its example without downloading either optional
  font and saved the expected text, tables, and images.
- Existing font-loader tests passed, including download failure and retry.

## Reproduce startup timing

Build a fresh product package with `build/office-product.py`, serve it with
compression, and run:

```sh
node test/office-startup-web.mjs \
  --url 'http://127.0.0.1:8154/writer/?start=new' \
  --out /tmp/startup.json --mbps 10 --latency-ms 40
```

Omit the network options for an unthrottled live-site check. The tool starts
its own temporary browser profile and records cold and warm loads, resource
sizes, phases, first-frame time, and when pending font downloads finish.

## Follow-up: earlier downloads and stronger gzip

The next pass preloads the app and renderer at the moment an editor action
starts, overlapping their transfer with the host's JavaScript import chain.
The standalone Office packager emits matching, versioned preload links in the
HTML head, including the font manifest. The product introduction still fetches
no runtime before an action.

An optional build-only Zopfli step shrinks the app's gzip file from 7,722,647
to 7,386,914 bytes. Decompressing either produces the exact same 21,210,560-byte
WASM binary. Browser decoding and app code are unchanged. The optional build
setting is `STARLING_ZOPFLI_PYTHON`, pointing to a Python with `zopfli` installed.
Existing stages can use `build/tools/optimize-web-gzip.py` before packaging.

Same controlled conditions as above, three fresh profiles per version and a
cached reload each. Before is the already optimized font-loading deployment;
after adds preload and stronger gzip. Run summaries are in
[office-web-startup-20261026-followup.json](office-web-startup-20261026-followup.json).

| Median metric | Before | After |
| --- | ---: | ---: |
| First frame, cold | 9.80 s | 9.38 s |
| Fonts settled, cold | 10.35 s | 9.95 s |
| Same-origin startup resource transfers | 11.97 MB | 11.63 MB |
| App download begins after navigation | 280 ms | 162 ms |
| First frame, cached | 0.46 s | 0.44 s |

This is an additional 4% improvement in first-frame time under the tested
network conditions. Cached timing is essentially unchanged. Each preloaded
app and renderer downloaded once, with no duplicate requests. Blank Writer
screenshots were pixel-identical. Writer, Slides, and Sheets examples opened
and saved with existing content checks passing. Standalone Writer also saved
its populated example and fetched each preloaded resource once. Packaging was
checked for idempotence and matching content versions; gzip checks cover
byte preservation, repeated compression, and invalid-input rejection.
