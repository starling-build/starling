# Starling Office website

The page focuses on Writer, Slides, and Sheets. Each app has a document preview,
three short capability labels, one suggestion to try, and an Open button. Both
the button and the preview open the editor with the pictured example ready to
edit. There are no PDF or source-file download controls on the landing page.
The landing itself uses HTML/CSS and needs no JavaScript or WASM runtime.

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

`build/landing-pages.sh` packages only the landing and preview images. It rewrites
the local editor links to `writer.starling.build`, `slides.starling.build`, and
`sheets.starling.build`; generated runtimes and editable files are not included
in the landing package. Publish updated app builds as well as the landing to
make the same opening experience available on the public domains.

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
