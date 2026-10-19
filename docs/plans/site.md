# A site from a repository

Status: **MVP built 2026-10-18 (evening)** — see "Where it stands". A content
site whose pages are Writer documents in a git repository, published as a
static folder that GitHub Pages serves. No server, no sign-in: editing is
local, in the native app on a clone, and Publish is a commit and a push.

The user's framing (2026-10-18): "the real MVP would be to use GitHub as
repo to host all the content for a site, no backend needed", and then
"assume the GitHub repo is cloned locally, you run a local app or server
to modify local files, once done, commit push to remote repo". The
earlier idea of signing in with GitHub and committing from the browser is
parked (it needs a token-exchange function, Decap-style; see the wiki plan's
discussion); the wiki server (`docs/plans/wiki.md`) stays as the
enterprise tier and is untouched by this.

## What a site is

```
site.json          { "title": "…", "base": "/", "pages": [ {slug, title, children?}… ] }
pages/<slug>.json  each page as the document model (RichDocumentEnvelope)
docs/              the build — what GitHub Pages serves (main branch, /docs)
```

The first page in `site.json` is the home page. Routes are `/<slug>/`
under the base; the home page is the base itself. Slugs are flat (a
child's route does not include its parent's).

`examples/site/` is a four-page site to start from.

## The pieces

- **`OfficeApp --site-build <repo> [--out <dir>] [--web <stage>] [--base /p/]`**
  (`apps/OfficeApp/Sources/OfficeApp/Site/SiteModel.swift`, `SiteBuilder`):
  copies the web build in, copies the pages, writes `manifest.json` (title,
  base, home, tree) and `search.json` (slug, title, text per page), and
  writes one shell page per route — the app's index.html with
  `<base href>`, the og/description meta tags from the page's title and
  first paragraphs, `args: ['--site', '<base>']`, and the page's text in
  `<noscript>` (text for crawlers and script-less readers, not layout).
  `index.html` is the home page's shell, `404.html` the app for unknown
  routes, `.nojekyll` keeps Pages from running Jekyll. It refuses to write
  into a folder that has files and no manifest.
- **The reader** (`Site/SiteShell.swift`, `SiteRoot`): the wiki's look — the
  tree, search over `search.json` with snippets, the page drawn by the
  Writer in read mode, the address bar following the page in a tab. Over a
  writable store it adds New page, Edit (the whole Writer on the page,
  `HostedDocument`, Save writes the file) and Publish (a commit message,
  then build into `docs/`, `git add -A`, `git commit`, `git push`).
  `OfficeApp --site-publish <repo> [-m msg] [--out] [--web]` runs the same
  from a terminal or a script.
- **Stores** (`Site/SiteStore.swift`): `StaticSiteStore` fetches the built
  files by URL (a tab on Pages; natively `--site https://…`);
  `LocalSiteStore` is the clone on disk (native `--site <dir>`), with the
  web build from `--web`, `STARLING_WEB_STAGE`, or `.stage-web-OfficeApp`
  in the working directory.
- **Gates**: `test/site-build.sh` (the build's output, a rebuild, the
  refusal, a `/demo/` base, an edit followed by a rebuild, and a publish
  to a local bare remote) and
  `test/site-web.sh` (the built site served as Pages would, headless
  Chrome opening a page by URL, reading its text, moving by the tree with
  the address bar following, a search hit, and the same under `/demo/`).

## Publishing to GitHub Pages

1. Create a repository from `examples/site`, commit, push.
2. Clone it; `OfficeApp --site <clone>`; edit; Publish.
3. In the repository's settings, Pages → deploy from branch `main`, folder
   `/docs`. For a project site (`https://<user>.github.io/<repo>/`) set
   `"base": "/<repo>/"` in `site.json` first.

The build is ~60 MB on disk (the app, fonts, skwasm); Pages serves it
gzipped: app.wasm is 7.8 MB over the wire, skwasm.wasm 1.6 MB.

**The demo: https://starling-build.github.io/site-demo/** (repository
starling-build/site-demo, made 2026-10-18 from examples/site with
`"base": "/site-demo/"`, published with `--site-publish`, Pages set to
main `/docs` through the API; the first deploy took 32 s and the site
answered 45 s after the push). Measured from a cold headless Chrome on the
dev Mac: app.wasm downloads in 1.3 s, the app is running before 3 s, the
tab is titled "Publishing — Starling Site demo", the page's text is
drawn, and a tree click moves to /site-demo/about/.

## Where it stands

**2026-10-18 evening:** builder, reader, both stores, both gates, and the
demo live on GitHub Pages (above). Not yet: delete/rename/reorder of
pages (edit `site.json` by hand for now); images in pages ride inside the
page JSON, which is fine until a page carries many; a phone layout for
the Writer's ribbon when editing (the reader is fine on a phone).
