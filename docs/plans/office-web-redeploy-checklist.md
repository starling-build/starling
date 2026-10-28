# Office web redeploy checklist — prepared only

Status: **NOT EXECUTED. No live deployment is authorized.** The user must
explicitly say yes to deploying the reviewed release. Linux build/validation
and this checklist are authorized separately. Created 2026-10-28 by the
release/validation session; claims/results live in `word-gaps-tasks.md`.

## Scope and existing sites

| Host | Site repository / branch | Release content |
| --- | --- | --- |
| `office.starling.build` | `starling-build/office`, `main` | Product entry pages `/`, `/writer/`, `/slides/`, `/sheets/`; independently versioned app, host, renderer and fonts under `runtime/` |
| `writer.starling.build` | `starling-build/writer`, `main` | Writer host, example DOCX, Office WASM and versioned skwasm |
| `slides.starling.build` | `starling-build/slides`, `main` | Slides host/startup example PPTX, same tested Office WASM/skwasm |
| `sheets.starling.build` | `starling-build/sheets`, `main` | Sheets host/startup example XLSX, same tested Office WASM/skwasm |
| `openoffice.starling.build` | `starling-build/openoffice`, `main` | Static landing/download pages, images and video; links to app hosts. No embedded app/renderer in inspected live repository |
| `starling.build` | `starling-build/www`, `main` | Main static site; no renderer update required by this release |

A renderer-only/app-runtime release updates the first four repositories.
OpenOffice and the main landing site require separate reviewed content changes
before any publishing; do not republish them merely to update skwasm elsewhere.
Current Office live `build-info.json` records source `d12e334f`, renderer
`skwasm-11189c07f4eacad0`, and renderer SHA256
`84b927ad4caf211b6183d17e6c3c3ec4a75f135791f0a02c8013c90ed7347a6f`.
Capture fresh per-site revisions and manifests immediately before preparation;
these values are an inventory snapshot, not a rollback substitute.

## Required release inputs and gates

- Record the exact engine commit from `origin/starling` (current validation
  pin `bd7be6b10e590dbf4154169f72e9c8e3c157c4b1`), including ancestors
  `39bb8cb9328` and `6461fc4819e`, all ten Skia patch hashes, private native and
  skwasm hashes, compiler version and build arguments. Never select Google’s
  published skwasm. Do not use shared engine output directories as scratch.
- Record the exact Office source commit. Accepted first-line masks landed in
  `b3a14a93`; subsequent uncommitted fidelity experiments are excluded. If a
  later fidelity fix is selected, require its own complete gates first.
- **Do not replace the live optimized host with the older Office-branch host.**
  At this inventory, `origin/main` has product packaging and loading/cache
  improvements absent from `office`. Prepare a clean private release checkout
  based on main with the selected accepted Office commit merged. Resolve only
  reviewed differences, preserve host/font/cache behavior, and rebuild/retest
  that exact resulting commit. Do not deploy an untested merge or infer that
  the Linux office-tip result validates a different source snapshot.
- Keep at least 10 GB free. Native and browser must use the same patched
  engine revision. Verify both native engine variables, actual dynamic library
  resolution, staged skwasm hashes and that no layout test silently skipped.
- Run `test/office-layout.sh` with PyMuPDF available, including fractional
  advance/ink and fixed-frame PDF gates. Keep the expanded 11-page reference
  gate, native RELEASE results and owner full same-engine corpus pair attached
  to the selected rendering change. Existing ae5 mask evidence is 756 docs
  per mode, zero missing/drops/page changes and 530 native tests with two known
  skips; these receipts do not cover future source edits.
- Local browser gates must cover Writer/Slides/Sheets example startup,
  open/edit/save/reopen, DOCX table-of-contents navigation, PDF export,
  fixed-frame overlap witnesses, and Chinese deferred-font loading. Both
  Chromium and WebKit should pass. Preserve originals and compression fallbacks.
- Verify Brotli/gzip app payloads decompress to identical bytes; renderer
  Brotli equals raw skwasm; font alternatives equal originals. Preserve lazy
  optional Chinese fonts, no editor downloads on an idle product page,
  preload response reuse, immutable component hashes and recovery from failed
  cached responses. These are shipping behavior, not optional cleanup.

## Preparation commands — private directories only

The following are a recipe for a future concrete release, not commands run by
this checklist. Substitute recorded accepted SHAs before execution. Use a
fresh private checkout, not either fidelity or validation candidate checkout.

```sh
# Source selection, still no deployment:
git fetch origin main office
git worktree add --detach /tmp/starling-web-release SOURCE_MAIN_SHA
cd /tmp/starling-web-release
git merge --no-edit ACCEPTED_OFFICE_SHA
# If conflicts occur, review/resolution and new commit identity are mandatory.

export STARLING_ENGINE_OUT=/path/to/private/engine/src/out/host_release
export FLUTTER_SWIFT_ENGINE_OUT="$STARLING_ENGINE_OUT"
export STARLING_SKWASM_DIR=/path/to/private/engine/src/out/wasm_release/flutter_web_sdk/canvaskit
export OFFICE_FONT_SOURCE=bundled
# Select the installed Swift toolchain and its matching WASM SDK via PATH.
swift build -c release --package-path apps/OfficeApp --scratch-path .build-release
build/web-app.sh OfficeApp --package apps/OfficeApp --check
export OFFICE_BIN=/absolute/path/to/.build-release/PLATFORM/release/OfficeApp
export OFFICE_PYTHON=/path/to/pymupdf-venv/bin/python
PORT=18137 test/office-layout.sh
```

Use the repository's Linux build wrappers/compatibility flags if the Swift
6.2.4/Ubuntu26.04 `<cmath>` issue applies. A fresh build and generated manifests
must identify the actual engine; copying an old executable is not a rebuild.

Create a fresh release package directory. The package must contain:

1. A runtime copied from the tested `.stage-web-OfficeApp`: optimized host,
   `font-loader.js`, `keymap.js`, gzip/Brotli app, fonts/manifest and the exact
   tested renderer. Give the renderer a directory name derived from the
   combined skwasm.js/WASM hashes; update the host references before packaging.
2. `build-info.json` with source/engine revisions, patch and artifact hashes,
   compiler, timestamp, and gate receipts. Compute hashes after compression.
3. Product pages using the existing optimized packager:

   ```sh
   python3 build/office-product.py --runtime /tmp/RELEASE/runtime --out /tmp/RELEASE/office
   ```

4. Three standalone copies of that runtime, configured separately:

   ```sh
   python3 build/tools/office-web-start.py /tmp/RELEASE/writer writer
   python3 build/tools/office-web-start.py /tmp/RELEASE/slides slides
   python3 build/tools/office-web-start.py /tmp/RELEASE/sheets sheets
   ```

   Preserve/set titles, the appropriate current icons, CNAME, `.nojekyll`,
   startup examples and provenance. One build is shared, not independently
   rebuilt during three deployments. Ensure examples actually open.

Serve all four packages on private local ports. Representative existing gates:

```sh
python3 test/office-examples-web.py --writer-url http://127.0.0.1:18175/ --slides-url http://127.0.0.1:18176/ --sheets-url http://127.0.0.1:18177/
python3 test/writer-local-file-web.py --entry-page --url http://127.0.0.1:18174/writer/ --out /tmp/RELEASE/file-check --load-ms 25000
node test/office-brotli-web.mjs --url 'http://127.0.0.1:18174/writer/?start=new' --standalone http://127.0.0.1:18175/
# Also run office-product-cache.py and office-cache-web.mjs per ui/office/README.md
# against old/new packages served from the same origin, including stale-cache mode.
```

The 2026-10-27 package/deploy scripts under `/tmp/starling-office-release-20261027`
are historical examples only: paths, source revision, parent assumptions and
payload hashes are stale. Do not rerun them unchanged. The stock
`build/web-deploy.sh` builds/pushes immediately and replaces the destination
root, so it is unsuitable for this approval-gated, retain-old-assets release.

## Approval boundary and actual publish commands

Before asking for the user's yes, prepare all four local packages and gates,
clone each destination into a clean private deployment checkout, record its
current `main` SHA, and produce reviewable diffs and a per-site hash manifest.
Overlay new package files while **retaining old content-addressed runtime and
renderer directories** for cached HTML; never blanket-delete those directories.
Preserve CNAME, analytics, icons, robots and sitemap. Stop on unexpected source
or deployment-repository changes and reconcile before approval.

After the user explicitly approves this particular reviewed release:

```sh
# Repeat for each reviewed checkout: office, writer, slides, sheets.
# Verify current remote main still equals the recorded pre-deploy SHA first.
git -C /tmp/RELEASE/deploy/office diff --check
git -C /tmp/RELEASE/deploy/office add -A
git -C /tmp/RELEASE/deploy/office commit -m 'Deploy validated Office SOURCE_SHA / engine ENGINE_SHA'
# Prepare equivalent commits for writer/slides/sheets before the first push.
git -C /tmp/RELEASE/deploy/office push origin HEAD:main
git -C /tmp/RELEASE/deploy/writer push origin HEAD:main
git -C /tmp/RELEASE/deploy/slides push origin HEAD:main
git -C /tmp/RELEASE/deploy/sheets push origin HEAD:main
```

No force pushes. Deployments are not atomic across sites: record each push,
wait for its GitHub Pages build and inspect the public response before declaring
success. Verify live manifests and fetched artifact hashes, new and cached
browser startup, all three examples, save/reopen/PDF and fallback transports.
On a failed site, stop further pushes and report the exact affected host.
Rollback uses the recorded prior content in a new commit (never rewrites
history), while preserving both old and newly referenced immutable assets.

## Current execution record

- Checklist prepared only; no release package, site commit or push executed.
- Linux private-engine and office-tip parity validation is a separate board
  claim. Append its final evidence path/hash here when complete.
- Redeployment awaits a concrete prepared release and the user's explicit yes.
