# Starling Office landing page

`openoffice.starling.build` is a six-slide presentation rendered by Starling
Slides. The content lives in editable PPTX files; the HTML provides navigation,
app/source links and deck downloads. The slides introduce
the open source suite, feature Writer, Slides, and Sheets individually, describe
the platform roadmap, and invite contributions. Each app has a dedicated
feature panel; Writer, Slides, and Sheets link to their public apps.

## Build and preview

Build native OfficeApp using `apps/OfficeApp/README.md`, then prepare the browser
runtime and decks from the repository root:

```sh
build/web-app.sh OfficeApp --package apps/OfficeApp
build/office-landing.sh
python3 -m http.server 8006 --bind 0.0.0.0 --directory ui/openoffice
```

`OFFICE_BIN` can select the native executable; its default is
`apps/OfficeApp/.build/release/OfficeApp`. Open http://localhost:8006, or use the
computer's LAN address from a phone on the same Wi-Fi. With that server running,
regenerate the previews from the live Slides canvas:

```sh
node build/tools/office-landing-posters.mjs http://127.0.0.1:8006/
```

`OfficeLandingDeck.swift` defines the initial presentation. The preparation
script regenerates `slides/landing-wide.pptx` and `slides/landing-tall.pptx`, so
keep direct deck edits elsewhere before running it. Both decks contain editable
text and shapes. Writer, Slides, and Sheets each use an editable illustration
made from slide shapes rather than app screenshots.

The page chooses a wide or portrait deck from the canvas dimensions and keeps
the current slide during rotation. Buttons, arrow keys, taps, and horizontal
swipes navigate the live app. PNG previews of those same slides are available
immediately and remain navigable if the runtime cannot start. Each slide has
an accessible description. Writer links open https://writer.starling.build/,
Slides links open https://slides.starling.build/, and Sheets links open
https://sheets.starling.build/.

The browser starts OfficeApp at `/office-landing` with both PPTXs as startup
files. It uses the app's existing slideshow and painter. The default OfficeApp
route still opens Writer. More implementation details and validation are in
`docs/plans/slides.md`.

## Hosting and publishing

The public site uses GitHub Pages in https://github.com/starling-build/openoffice,
serving `main` from the repository root at https://openoffice.starling.build/.

Publish `index.html`, `styles.css`, `slides.js`, `favicon.svg`, `slides/`,
`runtime.json`, and the runtime directory named by that manifest, together with
`CNAME` and an empty `.nojekyll`. Runtime files are ignored build outputs in this
source checkout; include them explicitly in the deployment checkout. Keep
`CNAME` set to `openoffice.starling.build`. Commit and push to the deployment
repository's `main`, then check its Pages deployment.

Cloudflare's DNS-only `openoffice` CNAME points to `starling-build.github.io`.
Keep that record and the Pages custom domain aligned. GitHub provisions TLS.
Do not run `../deploy.sh` for this page: it publishes the desktop site at
`starling.build` and does not include this directory.

## Deployment receipt — 2026-10-01

The Slides landing page is live at https://openoffice.starling.build/ from
`starling-build/openoffice` commit `58fc08a16bcd4f26ca74601d7f390f59fedf1804`.
[GitHub Pages run 36854271363](https://github.com/starling-build/openoffice/actions/runs/36854271363)
succeeded. The deployed manifest selects `runtime/d7c032408807e9aa/`.
The six-slide deck features Writer, Slides, and Sheets. The deployed HTML
pins its stylesheet and controller with content-hash query parameters; the
controller revision `04f0ac3f4aed0755` also versions the PPTXs and previews. Existing embed assets remain available for older cached pages.

Production checks verified HTTPS, the live Slides renderer, keyboard and phone
navigation, rotation, text access, deck downloads, and fallback previews under
an intentionally blocked runtime request. Critical assets matched the local
package by SHA-256. At deployment time, source changes were uncommitted in `starling-codex`;
the deployment repository contains the published build artifacts.

## Local integration — 2026-10-07

The landing presentation is integrated on the `office` branch, including
its Sheets browser open/save support and layout parity gate (`333b2864`). The landing page stays
an editable six-slide presentation rendered by Slides, with wide and portrait
PPTX sources; the newer Office browser open/save behavior is preserved.

The native landing-deck and header/footer tests passed (five tests), as did
the four font-loader tests. The Office WebAssembly build passed, and the local
package selects `runtime/4fec905713b8f2f7/`. Browser checks passed for live
playback, desktop and portrait navigation, rotation preserving the current
slide, accessible text, and preview navigation with the runtime blocked.
This validates the local source and build; it does not change the production
deployment receipt above.
