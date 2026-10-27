# Starling Office product website

`office.starling.build` is a task-oriented entry to the existing Swift/WASM
editors. The project landing page remains `openoffice.starling.build`.
The homepage accepts DOCX, XLSX, and PPTX files; `/writer/`, `/sheets/`, and
`/slides/` give each task a useful, crawlable entry page. Each offers opening
a local file, creating a blank file, and editing a bundled example.

The start screen introduces the suite with a short heading, one sentence, and
three benefits (free and open source, no account, no cloud uploads), followed
immediately by the file controls. It uses an app sidebar, a local-file opener, blank-file cards,
and compact example rows. Help is collapsed. There are no promotional hero,
feature, or screenshot sections; the OpenOffice site provides that introduction.
The HTML/CSS entry pages require no editor download until an action is chosen.
The small JavaScript launcher passes a local file through an in-memory blob URL
to the existing `initialFiles` bridge. It does not upload or persist documents.
The editor, renderer, and fonts are hosted on the same origin. The editor keeps
its existing file picker, Save behavior, and unsaved-change warning. Only DOCX,
XLSX, and PPTX are advertised; opening does not promise lossless compatibility.

## Package and preview

Use a tested deployment checkout or a compatible `build/web-app.sh` stage:

```sh
python3 build/office-product.py --runtime /path/to/writer-deployment --out /tmp/office-product
python3 -m http.server 8152 --bind 0.0.0.0 --directory /tmp/office-product
```

The output must be new. It includes all four pages, local assets, examples,
robots.txt, sitemap.xml, CNAME, and one shared runtime. The runtime directory
is content-addressed, including its JS imports and fonts. A build-info.json
retains deployment provenance when available. Font URLs are rewritten for
deep entry pages. Existing app and landing deployments are not modified.

`?start=new` and `?start=example` are supported on the three app pages. Each
canonical URL excludes these launch parameters. The page source contains
the headings, features, navigation, and FAQs without running JavaScript.

## Publication

Publish the package root to a separate static host, with the custom domain
`office.starling.build`. Configure DNS for that host and HTTPS before sharing
the production URL. Do not publish over the `openoffice` deployment repo.
Verify all three examples open and save using `test/office-examples-web.py`
with the new URLs ending in `?start=example`, and check the local file workflow.
For the product page's file picker, run:

```sh
python3 test/writer-local-file-web.py --entry-page --url http://127.0.0.1:8152/writer/ --out /tmp/product-file-check --load-ms 25000
```

Then verify the domain in Google Search Console and submit `/sitemap.xml`.
Packaging alone neither creates DNS records nor submits pages to Google.

Product names are Writer, Slides, and Sheets. Microsoft names appear only in
file-compatibility descriptions. Only `/writer/`, `/slides/`, and `/sheets/`
are published as app entry pages and included in the sitemap. The former
`/word/`, `/excel/`, and `/powerpoint/` addresses are removed, with no redirects.

## Analytics

`ui/cloudflare-analytics.js` loads Cloudflare Web Analytics on
`office.starling.build` and `openoffice.starling.build`, using the existing
Starling site token from `ui/main.js`. Local previews do not send analytics.
Packaging includes and versions the loader; it does not add document-content
tracking or custom editor events.

## Startup performance

Optional document fonts are requested only when used. Both new builds and
repackaged runtimes apply `build/tools/office_web_fonts.py`; the effective font
manifest is included in the runtime URL hash. The launcher overlaps fetching
the manifest and host module. See `docs/perf/office-web-startup-20261026.md`
for measured improvements and rendering checks.

The product launcher preloads the app and renderer only after an editor action.
Standalone Office pages start these assets and the font manifest in the HTML
head. The host consumes the original fetch responses, avoiding repeated downloads
in browsers that do not reuse preload links; visiting the product introduction does not download an editor.

For smaller standard-gzip release assets, install `zopfli` in a build-only
Python environment and set `STARLING_ZOPFLI_PYTHON` to that interpreter when
running `build/web-app.sh`. Alternatively, before packaging an existing stage:

```sh
/path/to/build-venv/bin/python build/tools/optimize-web-gzip.py /path/to/stage/app.wasm.gz
```

This optional step verifies the decompressed bytes and keeps the smaller file.
It adds no browser dependency. Repackage after compression so asset versions
reflect the final bytes.

When `brotli` is available, release builds also produce `app.wasm.br` at quality
11. Product and standalone Office pages select it using native
`DecompressionStream('brotli')` feature detection. Browsers without that decoder
use gzip; a missing or invalid Brotli response also falls back to gzip. Both
representations must decompress to the same app. Keep the gzip fallback when
publishing. Packaging older hosts remains supported without the new preload
path; current hosts advertise `supportsPreloadedAssets`.

For browser coverage, install Playwright and its WebKit browser in a test-only
environment, then run `test/office-brotli-web.mjs --url PRODUCT_WRITER_URL`
(the URL ends in `?start=new`), optionally with `--standalone WRITER_URL`.
`PLAYWRIGHT_MODULE` can point at that environment's `node_modules/playwright`.
This checks native Brotli, unsupported decoding, missing/corrupt responses,
standalone startup, and that idle product pages download no editor.
See `docs/perf/office-web-startup-20261026-webkit.md` for measured results.

Font downloads also have optional Brotli alternatives. Office release builds
with `brotli` installed run `build/tools/compress-web-fonts.py`; existing stages
can run that helper before packaging. It verifies that every alternative
restores the exact TTF/OTF bytes, then adds `brotli` URLs to the manifest.
Keep the originals for unsupported browsers and automatic failure recovery.
Both eager and deferred fonts use this transport, without changing which fonts
are optional. The PDF backend still receives original font bytes.
See `docs/perf/office-web-startup-20261026-font-transport.md` for measurements.
