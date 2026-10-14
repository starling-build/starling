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
features, DOCX/PPTX/XLSX support, and platform status. File formats are mentioned
in the suite introduction rather than in a separate compatibility section.
The browser apps are live. Desktop packages cover macOS Apple silicon, Windows
x86_64 (portable ZIP), and Linux x86_64 (DEB and Flatpak). Download links in the
navigation, hero, and footer open `download.html`. Platform details live on that
page rather than in a separate landing section. It has
platform icons, direct package links, and installation instructions. A small
optional script highlights the browser's OS; iPhone, iPad (including desktop
mode), Android, and ChromeOS instead get a browser-app link. OS detection does
not assume CPU architecture or a Linux distribution. All platforms remain
available, including with JavaScript disabled.

Version 0.1.0 downloads link directly to the published GitHub release assets
under `releases/download/office-v0.1.0/`. The release-notes link opens that
specific version. When
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
nine-slide presentation, and `--args --sheets` opens the budget.

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
checks that the handbook, nine-slide deck, and five-tab workbook preserve their
feature content. Use `--writer-url`, `--slides-url`, and `--sheets-url` to check
staged sites first. The test uses temporary browser
profiles and downloads; it does not touch user documents.

Publish the `office/` package to `starling-build/openoffice` (`main`, GitHub Pages),
keeping `openoffice.starling.build`. `ui/deploy.sh` publishes the main Starling
site, not Office. Packaging does not deploy anything.

## Preview images

`images/*-sample.png` show the first page/slide/sheet of the fictional garden
showcases, rendered by Office itself with `build/tools/office-example-previews.py`.
Writer previews the handbook's picture, headings, and lists; Slides previews a
column chart; Sheets previews its budget table, conditional formats, and chart.
The documents contain more features on subsequent pages and tabs. See
`web/office/README.md` for the coverage map and regeneration commands. Keep these
images, HTML dimensions/captions, and `web/office/examples/` synchronized. Packaged
preview URLs include content hashes so returning visitors get the new images.

The old `slides/`, `slides.js`, and product-local `styles.css` remain legacy
presentation samples and are not part of the website build.
