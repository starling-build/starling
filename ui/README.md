# Starling landing pages

The landing pages use semantic HTML and responsive CSS, with normal document
scrolling and selectable text. The main site introduces Starling as an open
software factory: Terminal, Office, Desktop, and the shared SDK. Office and
Desktop each have a separate page with product details and direct action links.

- `index.html`: the software factory, applications, SDK, and open-source project.
- `openoffice/index.html`: Writer, Slides, Sheets, app previews, direct editor links, and a link to downloads.
- `openoffice/download.html`: direct desktop downloads and installation steps, with optional OS detection in `download.js`.
- `desktop/index.html`: desktop features, agent workspaces, 2D/3D views, film,
  and installation links. 3D is one feature of the broader desktop.
- `styles.css`: shared responsive typography and layouts for all three pages.
- `main.js`: legacy desktop hash redirects and production-only analytics.
- `img/`, `video/`: existing desktop captures, film, and captions.

The pages do not load the Office WASM runtime, render slide images, capture
keyboard navigation, or require JavaScript to read their content and use links.
Office leads with document previews and direct links to the editors, which open
with editable examples. There are no PDF or source-file download controls. Packaged application
links point to `writer.starling.build`, `slides.starling.build`, and
`sheets.starling.build`. The source link is `github.com/starling-build/starling`.

## Preview

```sh
python3 -m http.server --directory ui --bind 0.0.0.0 8011
```

Open `/`, `/openoffice/`, or `/desktop/`. The shared stylesheet is one directory
above each product page. For video seeking, use a server with byte-range support.
The video uses native controls, captions, and `preload="none"`.

## Package and publish

```sh
build/landing-pages.sh
```

This creates `.stage-landings/starling/` for `starling-build/www`, and
`.stage-landings/office/` for `starling-build/openoffice`. Choose a fresh output
directory if packaging again (`build/landing-pages.sh /tmp/new-package`).
Office's standalone package includes the shared stylesheet at its root, so its
`../styles.css` URL works both in local previews and at the custom domain root.
No Swift build or WASM files are needed. Desktop is included in the main package.

`ui/deploy.sh` packages and publishes the main Starling/desktop site to the
existing GitHub Pages repository. It replaces that deployment repository's site
content and pushes to `main`; run it only for an intended release. Publish the
Office package separately to the Office deployment repository's root. Each
package contains the correct CNAME and `.nojekyll`.

This source change does not by itself publish either public website. The old
slide decks and controllers are retained as presentation samples; they are not
included in the static website packages.

Legacy root links `#film`, `#install`, and `#perspectives` redirect to the
corresponding Desktop section when JavaScript is available. The pages' current
navigation always uses ordinary links. Analytics loads only on the main site's
production domains.

## Content and media

Product descriptions come from the repository and the previous landing decks.
Terminal retains its published `terminal-v0.2.0` release link. Desktop links to
the versioned 0.5.0 preview and its installation guide. The Office page distinguishes
live browser applications from the wider native-platform roadmap.

Office sample sources and preview export details are recorded in
`openoffice/README.md`. Its `images/` directory is included in
the standalone Office package. Preview images load lazily without an app runtime.
For working local app links, run `build/office-web-preview.sh` after building
OfficeApp. The public app deployments bundle the examples separately.

Desktop images and footage show the running desktop. The film has original
instrumental music and AI-generated narration. Sample film: Big Buck Bunny,
© 2008 Blender Foundation, https://www.bigbuckbunny.org/, CC BY 3.0,
https://creativecommons.org/licenses/by/3.0/, resized for playback. Attribution
is retained beside the video and in the film.
