# Office startup: independent cache versions and renderer compression

The product packager now versions four components independently: the app,
renderer, JavaScript host/imports, and font collection. Previously a change to
any one file changed every runtime URL. A loader or font update can now reuse
an unchanged app and renderer; app updates can reuse unchanged fonts.

Only these content-addressed product assets use `force-cache`. Their bytes
cannot change without changing their URLs. Failed HTTP responses are retried
with `reload` so a deployment-time cached 404 cannot permanently block startup.
Standalone unversioned fonts retain normal HTTP caching. User documents are
not included in this caching path. Release gzip output also omits filenames
and timestamps, preventing build-time metadata from changing cache versions.

The renderer uses a verified 1,391,139-byte Brotli alternative on supported
browsers, compared with about 1.8 MB under the previous HTTP gzip delivery.
Its decoded WASM is unchanged. Both product and standalone Writer select the
alternative before fetching; unsupported browsers and failed Brotli responses
use the original renderer URL. If both fail, initialization surfaces an error
instead of waiting indefinitely for the renderer callback.

## Reusing assets after an update

A test served two product packages from one origin, differing only in the
loader's contents. Responses had `Cache-Control: max-age=0`, deliberately
expiring immediately. Fresh persistent browser profiles opened the first
release, then the second, confirming the changed loader URL and unchanged
app/renderer/font URLs. The second load transferred zero binary/font payload
bytes in both Chrome and WebKit. Server request logs independently confirmed
no repeated WASM or font-file requests. Small loader, page, and metadata
requests are not included in that claim.

The repeat first frame was approximately 0.24 seconds in Chrome and 0.59 seconds
in WebKit on the local, unthrottled server. These are cache-reuse checks, not
phone or first-visit timings. Browser retention still matters: private contexts
in this environment did not retain all large responses. The test uses normal,
disk-backed profiles and does not promise persistent retention in every browser.

Run `python3 test/office-product-cache.py` to verify URL boundaries. For the
browser check, overlay the two packaged runtime directories into one served
root, put their Writer HTML at separate URLs, then run
`test/office-cache-web.mjs --before URL --after URL --stale true` against a
server using `max-age=0`. Set `PLAYWRIGHT_MODULE` to a test-only Playwright
installation and use `--engine chromium` for installed Chrome.

## Cold-start measurement

Three fresh desktop WebKit browsers/contexts per version, alternating runs;
1440 × 1000, no CPU throttle. The local servers share a 10 Mbps response-body
rate limit across connections and delay each response by 40 ms. Writer opens
its default welcome document. Before is source 9726779e / Office deployment
91c943e. The report JSON includes cold-load samples and the separate cache tests.

| Median cold-load metric | Before | After |
| --- | ---: | ---: |
| First displayed frame | 8.02 s | 7.80 s |
| Same-origin resource transfer | 9.119 MB | 8.727 MB |

[Run data](office-web-startup-20261026-component-cache.json).

These are desktop WebKit results, not actual iPhone measurements. The cold
before/after screenshots were pixel-identical. First-visit Chrome continues
using the original renderer through HTTP compression; its download budget is
essentially unchanged: a regression check measured 11.63 MB and 9.33 seconds
under the existing 10 Mbps / 40 ms Chrome CDP setup, with a 0.44-second cached
first frame. The first deployment using the new component paths
requires a fresh download; cache reuse applies to subsequent updates.

## Validation

- Packaging tests verify repeatable URLs, isolated changes to each component,
  effective font-policy versioning, valid published asset paths and older hosts.
- Eleven loader tests cover lossless fonts, aliases, deferred loading, retries,
  native-decoder fallback, immutable-only cache overrides and failed-cache reload.
- Real WebKit coverage includes missing/corrupt app, font and renderer files,
  a renderer that recovers after a 404, a completely missing renderer with a
  visible error, standalone Writer, and no runtime requests on idle pages.
- All three Office examples and the Chinese/Archivo document opened and saved.
  Four documents exported to 14 PDF pages with matching text, page dimensions
  and embedded font types. Raster comparison at 108 dpi differed in only 33 RGB
  channels, each by one intensity level.
- App WASM and font bytes are unchanged. Renderer Brotli decoding was verified
  against the original WASM before packaging. Chinese fonts remain deferred.
