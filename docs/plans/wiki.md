# Wiki — an enterprise documentation site built on Office

Status: **drafted 2026-10-18; W0 under way the same night** (see "Where it stands"). A Confluence-shaped site —
spaces, page trees, versions, comments, permissions, search — whose pages
are documents edited and drawn by the Office suite's Writer running as
WebAssembly. Companion to `office-overview.md`; the suite's own plans
(`office.md`, `office-editor.md`, `wasm.md`) carry what the editor is.
Defaults below are marked **[default]** the way `sheets.md` marks them, so
each can be overturned without unpicking the rest.

## What it is, in one paragraph

Confluence is a web of always-current pages owned by a server, with files
as attachments; SharePoint is a managed file share, where the file is the
truth and the server only holds bytes and metadata. This is the first,
with Word fidelity attached: the server owns the page as a structured
model (the Writer's own `RichDocument`), the wasm Writer is the only thing
that draws it — reading and editing alike — and `.docx`, Markdown and
PDF are imports and exports through the readers and writers the suite
already has. HTML appears nowhere but the app shell and the clipboard:
a page is laid out by our painter, not by CSS, which is the point — an
author gets Word's control over tabs, tables, columns and fonts, and
every page can look like a document because it is one.

## What "done" means for v1

A team signs in with the company's identity provider, makes a space,
builds a tree of pages, and edits them in the browser with the Writer.
Someone pastes a page link into chat; the recipient's client shows the
title and first paragraph, and clicking it opens the page in the app at
that heading. A Word document uploaded as a page looks like it did in
Word; a page tree exported to `.docx` or PDF opens in Word paginated. Two
people cannot overwrite each other (locks, then merge); every save is a
version with a readable diff and one-click restore; inline comments stick
to the text they were made on; search finds words inside pages and inside
attached `.docx`/`.pptx`/`.xlsx`, in Chinese as well as English.

Not v1: real-time co-editing (planned, W5), a native desktop or mobile
client (W6), accessibility for screen readers on the canvas, Jira-style
integrations, public (anonymous) sites.

## Decisions

- **The stored page is the model, not a file [default].** A page body
  is a `PageDocument`: a versioned JSON encoding of `RichDocument` (every
  field, lossless — the round-trip gate is `decode(encode(d)) == d`) plus
  a wiki envelope (links by page id, block nodes, comment anchors). Why not
  `.docx`: the server must index, diff, merge, resolve backlinks and anchor
  comments without a browser; from the model that is a `JSONDecoder`, from
  `.docx` it is an unzip and a print-oriented XML parse per read, and the
  wiki-only parts would live inside content controls that Word is free to
  rewrite. `.docx` is one call to `Docx.write` away whenever anyone wants
  the file; `Docx.read` turns an upload into a page.
- **The wasm Writer is the only renderer [default].** No server-side HTML
  of page bodies. The URL `/s/<space>/p/<page-id>/<slug>#<anchor>` serves
  the same shell for every page, with `og:title`/`og:description` meta
  tags filled from the stored title and first paragraph so Slack, Teams
  and mail unfurl it; the app reads the route (`starling.js` already
  passes `initialRoute` to `starling_initial_route`) and opens the page.
  In-app navigation pushes history; the app handles middle-click and
  "open in new tab" itself. Cmd-F routes to the Writer's find bar; copy
  already produces HTML and text; print is `PdfExport`, which runs in the
  browser build today.
- **Pages lay out in the Writer's flow mode [default].** `RichLayout` with
  `pageSetup == nil` is the unpaged flow; the wiki editor runs there, with
  a page-view toggle and paged export. Word calls this Web Layout.
- **Server in Swift on Linux, Hummingbird 2** over SwiftNIO for HTTP and
  WebSocket, `PostgresNIO` for Postgres, attachments on a local directory
  behind a `BlobStore` protocol (S3-compatible later). The server does not
  link the suite (see Open questions): conversions — a `.docx` upload to a
  page, a page back to `.docx`, a PDF — shell out to the headless
  `OfficeApp` binary, which already builds on Linux and now has
  `--page-json` / `--page-docx` beside `--deck-pdf`.
- **Same origin for app and API [default]**: the server serves the app's
  static files and `/api/*`, so the session cookie (httpOnly, SameSite)
  needs no CORS and no token plumbing in the wasm host.
- **Stable paragraph identity comes from Word's own id.** Each
  `RichParagraph` gains an `id` (a 32-bit random, printed as 8 hex), read
  from `w14:paraId` when a `.docx` carries one and written back as it. A
  page that goes to Word and back keeps the identities its comments and
  merge anchors depend on.
- **Collaboration in three steps, each shipped** (see below): locks; then
  optimistic save with paragraph-level three-way merge; then real-time
  co-editing over a serialised `EditOp` log. Step one is built so step
  three is an addition.

## Shape of the code

```
wiki/                          one SwiftPM package, Linux and macOS
  Sources/WikiServer/          Hummingbird app: routes, auth, sessions
  Sources/WikiStore/           Postgres schema + queries, BlobStore, search
  Sources/WikiModel/           page envelope, op types, OT transform,
                               sequencer — pure Swift, no sdk
  Sources/wiki-admin/          CLI: migrate, create-space, import, export
  Tests/
apps/OfficeApp/
  Sources/OfficeApp/Wiki/      the client: space tree, page chrome,
                               comments pane, history, WikiSession (API);
                               PageDiff and PageMerge live here too (they
                               need the model, which the server lacks)
sdk/Sources/Flutter/RichText/  RichDocumentCodec.swift: Codable model,
                               RichDocumentEnvelope (schema + document),
                               paragraph ids
sdk/Sources/FlutterWeb/        host bridge: fetch + WebSocket + history
web/host/starling.js           the JS half of the same bridge
```

| Layer | Where | What |
| --- | --- | --- |
| Page model | `WikiModel/PageDocument.swift` | `RichDocument` JSON codec (schema v1), envelope: title, parent, labels, blocks, link targets, comment anchors |
| Diff | `WikiModel/PageDiff.swift` | paragraph alignment by id then LCS on text, run-level within a paragraph; renders as a `RichDocument` with change styles the Writer draws |
| Merge | `WikiModel/PageMerge.swift` | three-way at paragraph granularity; conflicts surface as both versions side by side in the page |
| Ops | `WikiModel/PageOps.swift` | `EditOp` ⇄ JSON, op log per page version (W5 uses it; W1 records it) |
| Store | `WikiStore/Schema.sql`, `Queries.swift` | spaces, pages, page_versions (immutable), locks, users, groups, grants, comments, attachments, audit, search index |
| API | `WikiServer/Routes/*.swift` | `/api/v1/spaces`, `/pages`, `/pages/:id/versions`, `/lock`, `/comments`, `/attachments`, `/search`, `/import`, `/export` |
| Shell | `WikiServer/Shell.swift` | the one `index.html` per request with meta tags filled; everything else static |
| Client | `OfficeApp/Wiki/*.swift` | `WikiShell` beside `WriterShell`/`SlidesShell`/`SheetsShell`, keyed by root; `WikiSession` wraps the API over the host fetch bridge |

The suite's rule holds: model, codec, diff and merge are plain Swift with
no engine dependency, so the same code runs in the browser, on the server
and in `test/run.sh`.

## The page model

`PageDocument`:

```
{ "schema": 1,
  "title": "…", "space": "ENG", "parent": "<page-id>", "labels": [...],
  "body": <RichDocument, every field>,
  "links":   [ { "para": "1a2b3c4d", "range": [12, 20], "page": "<id>", "anchor": "…" } ],
  "blocks":  [ { "para": "…", "kind": "panel|code|expand|toc|children|status|sheet|slide", "props": {…} } ],
  "anchors": [ { "id": "<comment-id>", "para": "…", "range": [0, 7] } ] }
```

- **Links** are by page id, never title, so renames do not break them;
  the server derives backlinks from this table on save. On `.docx` export
  they become hyperlinks to the site URL; on import, site URLs become
  links again.
- **Blocks** are typed nodes keyed to a paragraph: info/warning/note
  panels, code (language), expand (title), table of contents, children
  list, status lozenge, an embedded Sheets range (workbook attachment +
  range, drawn live by `SheetGrid`), an embedded slide (deck attachment +
  index, drawn by `SlidePainter`). The Writer draws each through a block
  painter; `.docx` export writes each as a tagged content control
  (`w:sdt`) around ordinary paragraphs so Word shows the content, and
  import reads the tag back into a block.
- **Comment anchors** are (paragraph id, UTF-16 range) and are rebased on
  every edit by the controller's `RichChange` stream — the same path the
  spell checker's marks already follow. On `.docx` export they become Word
  comments; on import Word comments become inline comments (today
  `Docx.swift` keeps `comments.xml` whole and opaque — this is where that
  changes).

## Collaboration, in three shipped steps

1. **Locks (W1).** Open for edit takes a lock with a 5-minute heartbeat;
   everyone else sees "<name> is editing" and reads. Save writes a
   version and releases. A dropped browser releases on heartbeat timeout.
2. **Optimistic save with merge (W3).** No lock; save carries the base
   version id. If the base is still the tip the save lands; otherwise the
   server runs `PageMerge` against the tip — disjoint paragraphs merge,
   the same paragraph touched twice becomes a conflict block the author
   resolves in the Writer. This is what Confluence shipped for a decade.
3. **Real-time co-editing (W5).** The client streams serialised `EditOp`s
   over the WebSocket; the server is the sequencer (it orders ops per
   page, clients rebase the ops they have not yet had acknowledged —
   server-ordered OT [default] over a CRDT, because one server already
   exists and the ops are already there; Peritext is the fallback design
   if offline editing in W6 needs convergence without a sequencer).
   Presence and remote carets ride the same socket.

## Phases

Each phase ends with a gate in `test/`, headless where possible, Chrome
where not (the `docx-web-render.sh` pattern), and with `office-overview.md`'s
status table gaining the wiki's row.

**W0 — groundwork in the suite** (nothing user-visible)
- `RichParagraph.id`, read from / written as `w14:paraId`; `RichDocument`
  invariants and `normalize()` keep ids through split and join (split
  keeps the id on the first half, the second gets a fresh one).
- `PageDocument` codec with the lossless round-trip gate over the docx
  corpus (`test/corpus/docx`): `Docx.read → encode → decode == Docx.read`.
- Writer flow mode as a chrome-level toggle (today reachable only by
  constructing a layout with no page setup); the layout-parity gate runs
  it.
- Host bridge on wasm: `starling_host_fetch` (method, url, headers, body,
  cookies same-origin) and `starling_host_socket` (WebSocket open, send,
  receive, close) in `starling.js`, surfaced in `FlutterWeb` as async
  Swift APIs; `starling_host_push_route` for history.
- **Composed text input in the browser.** Flagged missing in
  `office-overview.md`; a Chinese-speaking team cannot edit without it.
  Belongs here because W1 is unusable for the first customer without it.
- Gate: `test/run.sh` grows the codec and id tests; `office-layout.sh`
  gains the flow-mode row.

**W1 — a site that reads and edits**
- `wiki/` package: schema, migrations, `wiki-admin migrate`; users as
  local accounts for now (OIDC is W2) behind a session cookie.
- API: spaces, page tree, page get/put (a put is a new version), lock
  with heartbeat, attachments upload/download, import (`.docx`, `.md`
  via the existing readers), export of one page as `.docx`.
- Shell route with meta tags; static files for the app.
- Client: `WikiShell` — space sidebar with the tree, page in the Writer
  in flow mode, read/edit toggle that takes the lock, save, title row
  showing the lock holder, upload-a-Word-file-as-a-page.
- Gate: `test/wiki-api.sh` — start Postgres (docker compose in `test/`),
  migrate, create a space, import the 68-doc Chinese sample and the POI
  set as pages, fetch each back, decode equals the import; lock contention
  rejected; `test/wiki-web.sh` opens a page URL in Chrome and screenshots
  it at the heading.

**W2 — enterprise basics**
- OIDC sign-in (Entra ID, Okta, Keycloak tested); groups from the token;
  space roles (admin, write, read) and page restrictions inherited down
  the tree; an audit log table every mutation writes to.
- History: version list, diff of any two versions drawn by the Writer
  (`PageDiff` output is a `RichDocument` with insert/delete char styles),
  restore as a new version.
- Search: Postgres full-text over page plain text — **done 2026-10-19
  for pages** (`GET /api/v1/search`: the `simple` configuration through a
  GIN index, plus an ILIKE substring fallback that finds Chinese by its
  characters; `pg_jieba` can replace `simple` later); attachments indexed
  by text extracted with our own `Docx`/`Pptx`/`Xlsx` readers; results
  open the page at the first hit (client side still to do).
- Gate: `test/wiki-api.sh` gains permission matrix cases and a Chinese
  search case (a query word inside an attached `.xlsx` cell is found).

**W3 — the parts that make it a wiki**
- Optimistic save + `PageMerge` replaces locks as the default (locks stay
  as an explicit "lock this page" for policy documents).
- Comments: page-level threads; inline comments on a selection, anchored
  by paragraph id and rebased through `RichChange`; resolve; `.docx`
  export writes them as Word comments, import reads Word comments.
- Mentions (`@name`) with notifications (mail first, in-app bell second);
  watch a page or a space.
- Blocks: panels, code, expand, TOC, children, status; embedded Sheets
  range and slide; labels and a label page.
- Templates: a space's page templates are pages flagged as such.
- Gate: merge fixtures in `test/fixtures/wiki` (disjoint, same paragraph,
  reorder); comment round-trip through Word via `docx-word.sh`.

**W4 — in and out at scale**
- Export a page tree as one `.docx` (chapters per page, TOC field,
  page-break between pages) and as PDF via the headless Linux `OfficeApp`;
  measured against Word's print with the existing render gate.
- Confluence import: their space export (XHTML storage format + attachments)
  into pages, links and comments — the migration path from the product
  this replaces. Markdown-tree import for teams coming from a docs repo.
- Public API tokens and webhooks (page created, updated, commented).
- Gate: a sample Confluence export in `test/corpus/confluence` imports
  with every link resolved.

**W5 — real-time co-editing**
- `EditOp` serialisation and the per-page op log recorded from W1 on
  (every save stores its ops beside the snapshot).
- WebSocket session per open page; server-ordered rebase; presence and
  remote carets in `RichEditable`.
- Gate: a headless two-client test drives interleaved ops through the
  server and asserts convergence; the Chrome gate shows two tabs typing.

**W6 — desktop and offline**
- The native `OfficeApp` opens site URLs (`wiki://`) in `WikiShell`, with
  the same `WikiSession` over `URLSession`; offline edits queue as ops
  and replay on reconnect (convergence here is what would push W5 from
  server-ordered OT to a CRDT). iOS follows the suite's own iOS plan.

Cross-cutting, scheduled when they bite: accessibility (the SDK has
`Semantics`; the web host does not publish the tree — a canvas is silent
to a screen reader until it does); first-load size (`wasm-size.md`);
multi-tenancy (one deployment per company [default], revisited if hosting
is offered).

## Open questions

- ~~Hummingbird or Vapor~~ — **Hummingbird, decided 2026-10-18.**
- ~~Server-ordered OT vs CRDT for W5~~ — **server-ordered OT, decided
  2026-10-18.** W6's offline case rebases its queued ops on reconnect the
  same way a client with a slow link does; no CRDT.
- **Does the server link the suite?** `RichDocument` lives in the sdk's
  `Flutter` module, which links the engine (`libflutter_engine.so`) on
  Linux. A server that imports it ships the engine. **[default]** the
  server does NOT link the sdk: `wiki/` is pure Swift; page bodies are
  opaque JSON to it, and the client sends the derived facts it needs
  (title, plain text for search, link targets) alongside each save, with
  the headless `OfficeApp` CLI (`--page-json`, `--page-docx`) doing
  conversions for import and export. OT needs only positions (paragraph
  index/id, UTF-16 offsets), not the model. Revisit if `RichText` is ever
  split into an engine-free module.
- Does `PageDocument` carry the whole kept-parts bag `Docx.read` keeps for
  round-trip (styles, numbering, unknown parts)? **[default]** yes, as an
  opaque `kept` section, so an upload-edit-download trip loses nothing
  the suite would otherwise keep; trimmed later if page bodies grow.
- Where the first deployment runs. The dev box can host Postgres and the
  server for the gates; a real pilot wants a VM with a domain and the
  identity provider's redirect registered.

## Where it stands

**2026-10-19 (overnight from the draft): W0 done but for IME, W1 built and
gated server-side, the browser gate written and awaiting its first green.**

- W0: `RichParagraph.id` (Word's `w14:paraId` in and out, fresh ids on
  split), every model type `Codable`, `RichDocumentEnvelope` (schema 1),
  `OfficeApp --page-json / --page-docx / --page-roundtrip`,
  `test/wiki-codec.sh` — 327 of 327 readable corpus files round-trip
  exactly (8 the reader refuses, `deep-table-cell.docx` crashes the
  reader itself, a pre-existing recursion). The web host has fetch,
  WebSocket and history (`starling_host_http_request` and friends,
  `WebHTTP`/`WebSocketClient`/`WebHistory` in FlutterWeb); `index.html`
  passes the tab's path as the app's route. **Browser text input, 2026-10-18
  evening:** the page keeps a hidden `<textarea>` (`#starling-ime`) and
  focuses it when a text field takes focus — `SoftKeyboard.show()` from
  `RichEditable` and `TextBox`, carried by the new `starling_host_soft_
  keyboard` import; `FocusManager` calls `SoftKeyboard.focusMoved()` so
  focus landing on a non-field lets the keyboard go a beat later. Keys
  typed into the field go down the key path; what the browser composes
  (a phone's keyboard, an input method's committed text, a paste) comes
  back as `beforeinput`/`compositionend` text and is delivered through
  `starling_text` as down/up pairs, the iOS host's model. So an iPhone
  can sign in and type, and a desktop IME's committed text lands. **Still
  not done:** the `flutter/textinput` channel on web, so there is no
  inline marked text while composing (the candidates show in the
  browser's own popup, the text appears on commit) and no caret-anchored
  candidate window. That is the remaining IME item.
- W1: `wiki/` (Hummingbird 2.28, PostgresNIO 1.33): `wiki-server migrate |
  add-user | create-space | import | serve`; the API in
  `WikiServer/App.swift`; `test/wiki-api.sh` — 38 checks green against a
  throwaway database. The client: `apps/OfficeApp/Sources/OfficeApp/Wiki/`
  (`WikiTransport`, `WikiSession`, `WikiShell`), `--wiki <url>` natively,
  `/s/…` routes in a tab. `test/wiki-web.sh` drives the wasm build in
  headless Chrome (sign in, open by URL, click Edit, type, click Save; the
  API then shows the new version) and is green. The sidebar has a search
  box over `GET /api/v1/search`; the version link opens a history pane,
  an old version shows "Back to latest" and "Restore this version" (its
  body saved again on top of the tip); Delete has a confirm row. All
  three seen working in headless Chrome. The dev server runs on the Mac on
  the LAN at http://192.168.68.62:8080/s/ENG with `--dev-user dev`, so a
  phone needs no sign-in (dev / devpass otherwise; wiki/README.md restarts
  it). `test/wiki-web.sh` now also signs in by composed text, checks the
  hidden field took focus, and checks `--dev-user`. On a phone the editing
  toolbar's self-sized buttons each took a whole row and pushed the editor
  off the screen (fixed widths now), and the page sizes its canvas to the
  visual viewport so the editor lays out above the keyboard. Two bodies
  the first hours' server wrote as a hand-made envelope (before `{}` was
  the placeholder) did not decode — "This page's content cannot be read
  by this build" — and were reset to `{}` in the dev database; nothing
  else was ever written that way.
- WikiModel (W5's core, built early because it is pure): `PageOp`,
  `Transform`, `PageSequencer`, `PendingOps`; 14 convergence tests.
- Decided 2026-10-18 by the user: Hummingbird; server-ordered OT.

**Traps paid for (2026-10-19).**

- **The OfficeApp wasm build had not linked for a week** when this work
  reached it: a handful of commits had used `String.contains(String)`,
  `range(of:)` on a Substring, `NSLock`, `JSONSerialization` and a
  32-bit-overflowing literal, all of which resolve to the legacy
  Foundation module the web build deliberately leaves off the link
  (`docs/plans/wasm-size.md`). The quick tier's "web: size gate" builds
  CounterApp, not Office, so nothing caught it. The spellings that work
  are in `sdk/Sources/Flutter/Foundation/StringHelpers.swift`
  (`containsSubstring`, `findRange`, `trimmingWhitespace`), `"x" as
  Character` for one character, OfficeFonts' `_NoLock`, `Int64`/`Int32`
  literals. wasm-ld names an OBJECT file; under whole-module optimisation
  that is not the source file — `llvm-objdump -d -r x.o | awk '/^[0-9a-f]+ </
  {fn=$0} /SYMBOL/ {print fn}' | swift demangle` names the real caller.
  Worth a gate: `build/web-app.sh OfficeApp --package apps/OfficeApp`
  on every change to the suite.
- **Int is 32 bits on wasm, and a synthesised Decodable wants every
  key.** `Int(UInt32)` of an opaque colour trapped (`RuntimeError:
  unreachable`, no message) on the first real page; the codec now goes
  through `Int64`. And the server cannot hand-write a document body:
  defaulted properties are still required keys when decoding, so an
  empty page is `{}` and the client reads that as a blank document.
- **A dropped subtree was deactivated only at its root.** Clicking a
  button whose handler rebuilt the header without it trapped the web
  build: the button's HoverButton, dirtied by the click, stayed `.active`
  under a deactivated parent and built against inherited widgets that
  were gone (`FluentTheme.of` force-unwraps). Upstream deactivates
  recursively (`_InactiveElements.add`); now so do we. To read a wasm
  trap: `STARLING_WASM_NAMES=1 build/web-app.sh …`, then re-run its
  `wasm-opt` line with `-g` into the stage (the plain `--debug` module is
  too big for Chrome's parameter limit), and pass
  `eval "Error.stackTraceLimit=80"` to `web-drive.mjs` before the click.
- **Never drive the native app's GUI on the Mac with osascript/CGEvent
  while other sessions run there.** Keystrokes
meant for the wiki's sign-in form landed first in another session's
Slides window (undone with ⌘Z) and then in Word's Save dialog, raised by
the .docx oracle gate another session was running (left as found). Verify
the client in headless Chrome (`test/wiki-web.sh`, `build/tools/web-drive.mjs`),
which steals no focus; the native client is for a human.

Drafted 2026-10-18. The suite facts this plan rests on,
checked in-tree the same day: `RichLayout` has the flow mode
(`isPaged == false`); `RichDocumentController` already expresses every
mutation as an `EditOp`; `RichParagraph` has no id; `RichDocument` is not
`Codable`; `Docx.swift` keeps comments whole and opaque; `starling.js`
passes `initialRoute` and fetches `initialFiles` but offers Swift no fetch
or socket; composed text input is missing in the browser; `OfficeApp`
compiles and runs headless on Linux.
