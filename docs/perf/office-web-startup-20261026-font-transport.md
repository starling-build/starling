# Office startup: lossless font transport

Fonts now have optional Brotli transport files alongside their original TTF/OTF
files. The host decompresses them before handing bytes to the renderer. This
preserves the complete original font, including glyphs, hints and PDF embedding
data. It does not convert fonts to WOFF2 or remove glyphs.

`build/tools/compress-web-fonts.py` compresses and verifies all 83 files before
adding their alternatives to the manifest. The original files and all family,
fallback and lazy metadata remain. Release Office builds run this step when
Brotli is installed; existing stages can run the helper before packaging.
Product packaging rewrites and validates both URLs. Standalone pages version
the updated manifest and host; the host's font-loader import has a new query
so cached copies of the previous module cannot hide the added helper export.

Native Brotli-capable browsers fetch compressed fonts. Others request only the
original files. A missing, corrupt or failed compressed response retries the
original. The same path handles eager UI/default fonts and deferred document
fonts. Chinese fonts remain deferred.

## Measurement

Same setup as the preceding WebKit report: three fresh desktop WebKit contexts
per variant, alternating runs, 1440 × 1000, no CPU throttle. Local servers share
10 Mbps per server across response bodies and delay each response by 40 ms.
The page opens Writer's default welcome document. Before is source 1bcf097d /
Office deployment 969b44b; after adds compressed font transport only.

| Median cold-load metric | Before | After |
| --- | ---: | ---: |
| First displayed frame | 8.265 s | 7.968 s |
| Same-origin startup transfer | 9.576 MB | 9.119 MB |

This is about 0.46 MB less startup data and a 3.6% improvement in this controlled
desktop WebKit test, not a measurement on an iPhone. Screenshots were
pixel-identical. [Run data](office-web-startup-20261026-font-transport.json)
retains totals and individual font requests.

Across the full font collection, the alternatives total 20.35 MB versus
25.73 MB for gzip at level 6. Most fonts are deferred and are not startup
costs. The two Chinese faces together fall from 15.25 to 11.76 MB when needed;
neither was requested during default-document startup.

## Validation

- All 83 Brotli files decompress to byte-identical originals, checked during
  packaging. No application or renderer WASM changes.
- Nine loader unit tests cover shared aliases, lazy loading, exact bytes,
  unsupported Brotli, missing/corrupt/network responses and explicit retries.
- Real WebKit tests exercise native and unsupported decoding, app and font
  failures, standalone Writer, and no runtime fetch on an idle product page.
- Writer, Slides and Sheets opened and saved their populated examples in
  WebKit. Saved packages retained their expected text, tables, images, links,
  slides, charts and worksheets. A Chinese/Archivo Black document also saved.
- Before/after WebKit exports covered four documents and 14 PDF pages. Text,
  page dimensions and embedded font types match. Raster comparison at 108 dpi
  found only 42 changed RGB channels, each differing by one intensity level.
  The earlier WOFF2 embedding regression did not recur.
