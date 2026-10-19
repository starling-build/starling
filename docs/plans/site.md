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

## The reader as a document reader (2026-10-19)

The focus the user chose: not web pages but published documents — what
HTML cannot do is the page. So a page that came from a paged file keeps
its page setup in the stored form (`RichDocumentEnvelope.pageSetup`,
written by `--page-json`, by Writer's Save over a hosted document, and
read back by `--page-docx`), and the reader shows it as **pages** on a
desktop (headers, footers, page numbers, "Page 8 of 24", a page wider
than its room drawn smaller, whole) and as **flow** on a phone, with a
Pages/Flow switch. **Contents** lists the headings with the page each
starts on (`RichLayout.pageNumber(ofParagraph:)` over a layout of the
page view's own making); a click scrolls there. **Link to paragraph**
puts `#p=<paragraph id>` in the address bar, and opening such a link
scrolls that paragraph to the top, selected (`SiteShellState._reveal`:
the caret at the paragraph's START with `pendingReveal = .top`; a
selection whose caret sits at the end is revealed by its end and lands
at the foot of the view). **PDF** downloads the same painter's pages
(24 pages with pictures take ~15 s in a tab). `starling.debug('view' |
'pages' | 'toc' | 'caret' | 'status')` answer scripts; `test/site-web.sh`
drives all of it on `sample-paper` (the BoringCrypto security policy from
the fixtures, 24 pages, footnotes).

**The stored form was 37 to 1 against gzip**, and seconds to decode: the
synthesized coding wrote all 85 fields of the two style structs for every
paragraph and run. `RichDocumentSparseCoding.swift` (generated from the
declarations) writes only what differs from the default and reads a
missing key as the default, so older pages still decode. A text page went
from 13 KB to 3 KB, the security policy from 1.8 MB to 1.0 MB; the 327
corpus documents still round-trip exactly. Still heavy: government
documents whose tables carry kept OOXML per cell (`CellRef`:
continuation paragraphs and XML, borders XML) — the 临沧 notice is 4.0 MB
(134 KB gzipped), the 浙江 credit rules 7.1 MB (192 KB gzipped), and a
same-as-previous-paragraph coding of `cell` would halve the latter. A
model change, left for when the measured load in a tab says so.

**Chinese in a tab.** The web build shipped no CJK face, so every
Chinese character drew as a box — document and UI alike. `web/fonts/
NotoSansSC-VariableFont_wght.ttf` (OFL, 18 MB) is in the font manifest
as `?!`: deferred AND a glyph fallback. On the web `OfficeFonts.substitute`
maps any Chinese face name (宋体, 仿宋, 黑体, Word's list, or any name
with CJK characters) to "Noto Sans SC"; the paragraph builder asks the
page for a family it lacks (`starling_host_request_font`), the loader
fetches it, registers it, and — new — adds it to the glyph-fallback
chain, so the sidebar's titles in Carlito draw too. A Latin-only page
never fetches it (checked: `about` loads 0 Noto resources, the notice 1).
One sans face stands in for 仿宋/宋体/黑体 alike; a serif (Noto Serif SC)
is the next step for the official look, and so is measuring the
pagination against Word's print of these documents with the web faces.
Live from Pages, cold: the notice's JSON 149 KB in 0.2 s, the font 11.4 MB
gzipped in 4.2 s, the page as 34 pages — the first Chinese page a visitor
opens costs those four seconds once.

**Trap, paid for twice tonight:** a NEW file under `sdk/` is not noticed by
an incremental `swift build` in either scratch (`apps/OfficeApp/.build`
and `.build-web-OfficeApp`): the build "completes" in a second, the app
keeps the synthesized coding, and the browser says "This page's content
cannot be read by this build" against pages the native build wrote. Delete
the scratch's `*.yaml` and `build.db` and build again (sdk/CLAUDE.md's
recipe) — then watch for the file in the compile log.

## Where it stands

**2026-10-19:** builder, reader (pages, contents with page numbers,
paragraph links, PDF), both stores, both gates, the demo live on GitHub
Pages with one published document (the BoringCrypto security policy, 24
pages with footnotes). **The user's direction, 2026-10-19: Western
customers** — the two Chinese demo documents were removed from the demo
(they proved the format work; `test/corpus/docx` still holds them), and
the build ships the Chinese font only with a site that has Chinese text
(`SiteBuilder.pruneFonts`), so a Western site's `docs/` never carries the
18 MB.

**Later the same day:** Find in the page (the Find button or Ctrl+F;
typing selects the first match, Next or Ctrl+G the next); Ctrl+C puts
the selection on the system clipboard in a tab (`WebClipboard` in
FlutterWeb behind `Clipboard.provider`, text and HTML through
`navigator.clipboard`; a read answers empty when the browser refuses); a
finger scrolls the document and a tap places the caret (RichEditable's
touch path, confirmed on the user's iPhone); the read-only status page
follows the view. Over a clone: Import .docx… (the file panel; the
document becomes a page under the open one, ids assigned, page setup
kept — `--site-import <repo> <file> [--title] [--under]` from a
terminal), Rename, Delete (children move up), Move up/down among
siblings (`--site-move <repo> <slug> up|down`). `test/site-web.sh`
drives find, the double-click selection, a stubbed clipboard write and
the touch drag; `test/site-build.sh` the import and the move.

**Western demo documents (2026-10-19):** two NIST works, public domain
(csrc.nist.gov, CMVP Module Processes): the FIPS 140-3 security policy
template (81 headings, a table of contents) and the CMVP revalidation
change document (778 table cells), imported with `--site-import` and
credited in the demo's README. Sources tried and dropped: GOV.UK's
Word attachments are forms, not manuals, and its one large report is a
legacy .doc that textutil turns to garbage; the corpus's non-Chinese
documents are bug-tracker attachments of unknown licence.

**A text layer for screen readers (2026-10-19):** the canvas is a picture
to a screen reader and a crawler alike, so the shell page carries the
document's paragraphs and headings as hidden HTML (`<main
id="starling-text" class="starling-sr">`, h1–h3 and p, clipped to a pixel;
shown plainly with scripts off), and the reader replaces it as it moves
between pages (`WebAccessibility.setDocumentText` →
`starling_host_set_document_text`). It is the document's text in reading
order, not its layout; the reader's own controls (the tree, the buttons)
are still only on the canvas, which is the next accessibility step.

**Crawlers (2026-10-19):** with `"url"` in `site.json` the build writes
`sitemap.xml` (every route) and `robots.txt`; the demo has
`https://starling-build.github.io/site-demo`.

**Word and History (2026-10-19):** the reader's Word button downloads the
page as .docx (the source document, for a reader who wants Word); with
`"repository"` in `site.json` a History button opens the page's commits
on GitHub in a new tab (`hostOpenURL` reaches the page through the new
`starling_host_open_url` import — before it, a cross-origin link went to
`pushState`, which only warned). The text layer opens with every page as
a real link, so crawlers reach the whole site from any page. Link to
paragraph now copies the whole address (`starling_host_copy_location`,
the tab's `location.href`) as well as putting `#p=<id>` in the bar.

**Static exports (2026-10-19):** the build writes every page as
`<slug>/<slug>.pdf` (the same painter, with the site's web faces) and
`<slug>/<slug>.docx` beside its shell, links both from the text layer
("Download as PDF · Download as Word", for crawlers, screen readers and
scripts-off readers alike), and the reader's PDF and Word buttons open
those files instead of rendering in the tab — instant where the in-tab
PDF of a 24-page document took 15 s. The manifest says `exports: true`;
over a clone the buttons still render locally.

Not yet: a smaller stored form for table-heavy documents (above); the
reader's controls for screen readers; a phone layout for the Writer's
ribbon when editing (the reader is fine on a phone).
