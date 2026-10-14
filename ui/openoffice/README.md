# Starling Office website

The page introduces Writer, Slides, and Sheets as a free, open source suite for
familiar Office files. Each app has a short introduction, capability labels,
a document preview, one suggestion to try, and an Open button. Both
the button and the preview open the editor with the pictured example ready to
edit. There are no PDF or source-file download controls on the landing page.
The hero introduces the suite and links to downloads and the app sections.
Sample links live in each app section, without a duplicate hero panel.
The landing itself uses HTML/CSS and needs no JavaScript or WASM runtime.

The app section headings, Office header, and download-page header use the murmuration
icons in `ui/img/office/`. These are exact copies of the native application
icons in `build/office-gtk/starling-{writer,slides,sheets}.svg`; update the web
copies when those designs change. Writer's icon also represents the suite in
the header and browser tab, matching the desktop bundle. Both site packages
include the shared icons, with content hashes in their URLs to refresh caches.

Product copy follows `docs/plans/office-overview.md` (2026-10-13): current editing
features, DOCX/PPTX/XLSX support, compatibility testing, and platform status.
Compatibility is described as ongoing work, not a guarantee of perfect fidelity.
The browser apps are live. Desktop packages cover macOS Apple silicon, Windows
x86_64 (portable ZIP), and Linux x86_64 (DEB and Flatpak). Download links in the
navigation, hero, platforms section, and footer open `download.html`. It has
platform icons, direct package links, and installation instructions. A small
optional script highlights the browser's OS; iPhone, iPad (including desktop
mode), Android, and ChromeOS instead get a browser-app link. OS detection does
not assume CPU architecture or a Linux distribution. All platforms remain
available, including with JavaScript disabled.

Version 0.1.0 downloads currently use immutable public `dist/` URLs at commit
`f5f0e2760ab29568ba28d15b2d9e5786b9f845d8`, matching the release assets. The GitHub
release is still a draft; do not use its temporary `untagged-*` asset URLs.
Once published, these links can move to the versioned release assets. When
updating downloads, verify all four files, their architecture, size, and install
instructions. The sample captions describe the pictured files; the capability
labels describe the broader apps.

## Local preview

Build the browser app, then prepare all three editors:

```sh
build/web-app.sh OfficeApp --package apps/OfficeApp
build/office-web-preview.sh
python3 -m http.server --directory ui --bind 0.0.0.0 8011
```

Open `/openoffice/`. Its app links use `apps/writer/`, `apps/slides/`, and
`apps/sheets/`, generated under the ignored `ui/openoffice/apps/` directory.
The preview script also accepts a compatible, already-built stage as its first
argument. A rebuilt OfficeApp is required for startup example support.

## App startup and publishing

The editable examples live in `web/office/examples/`. The app host supplies the
file's bytes through `initialFiles` before Swift mounts, and its name as the
first app argument. `PickedFile.take` consumes the startup file once. The
regular Office file-opening path selects Writer, Slides, or Sheets from the
extension; File → New remains the ordinary blank-document action.

`build/tools/office-web-start.py` configures a staged app page and copies its
example. Both local preview and `build/web-deploy.sh` use this helper. For
OfficeApp, the default deployment opens the brief, `--args --slides` opens the
four-slide presentation, and `--args --sheets` opens the budget.

`build/landing-pages.sh` packages the landing, download page, and preview images. It rewrites
the local editor links to `writer.starling.build`, `slides.starling.build`, and
`sheets.starling.build`; generated runtimes and editable files are not included
in the landing package. Publish updated app builds as well as the landing to
make the same opening experience available on the public domains.

Verify the actual app startup after publishing, not only the landing links:

```sh
python3 test/office-examples-web.py
```

This drives Chrome, checks each example's name, saves through the editor, and
checks that the resulting presentation has four slides and a chart, and that
the budget retains its values, formulas, and chart. Use `--slides-url` and
`--sheets-url` to check staged sites first. The test uses temporary browser
profiles and downloads; it does not touch user documents.

Publish the `office/` package to `starling-build/openoffice` (`main`, GitHub Pages),
keeping `openoffice.starling.build`. `ui/deploy.sh` publishes the main Starling
site, not Office. Packaging does not deploy anything.

## Preview images

`images/*-sample.png` show the fictional community-garden examples rendered by
Office at revision `0975eb0c`. They are document output, not mock UI. Writer shows
headings, lists, and a table; Slides shows an editable chart and has speaker
notes; Sheets has formulas, filters, and a chart. Keep the pictures synchronized
with `web/office/examples/` when updating the examples.

The old `slides/`, `slides.js`, and product-local `styles.css` remain legacy
presentation samples and are not part of the website build.
