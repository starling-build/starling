# Starling Office landing page

Static landing page for `openoffice.starling.build`, separate from the desktop
showcase in `ui/`. No build step, JavaScript, external fonts, or dependencies.

The office site has its own visual identity: bold sans-serif typography, cobalt
blue accents, white document surfaces, a navy platform section, and a document
logo. Layouts have been checked at 320, 390, 768, and 1440 CSS pixels wide.

Preview from the repository root:

```sh
python3 -m http.server 8000 --directory ui/openoffice
```

Open http://localhost:8000. The document in the hero is an HTML/CSS illustration,
explicitly labeled as a preview, not a screenshot or an embedded editor. Writer
links open the real app at https://writer.starling.build.

Writer features are grounded in `apps/OfficeApp` and `docs/plans/office.md`.
Native platform names describe the roadmap, not downloadable releases. Source
links use the `office` branch, where Writer currently lives.

## Publish to the intended domain

Deploy this directory as its own static site. Serve `index.html`, `styles.css`,
and `favicon.svg` from the domain root, not `/openoffice/`. `CNAME` records the
intended GitHub Pages custom domain when using that provider. Configure the
domain's DNS and HTTPS with the chosen host.

Do not run `../deploy.sh` for this page: that script publishes the desktop site
to `starling.build`, and does not include this directory.

During inspection on 2026-09-30, Writer served its WebAssembly boot page but its
HTTPS certificate did not match `writer.starling.build`. Correct that certificate
before public launch so visitors can follow the primary call to action normally.
