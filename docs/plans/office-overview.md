# Office: where it stands, how it is built, how it is tested, what is next

As of 2026-10-13. The map over the four plan documents — `office.md`
(Writer and the suite), `office-editor.md` (the editor), `slides.md`,
`sheets.md`, `wasm.md` (the browser), `site.md` (a site from a git
repository, no server), and `wiki.md` (the documentation
site built on the suite, drafted 2026-10-18) — which carry the history and
the traps; this page is kept short and current.

## What it is

Office is one app, `apps/OfficeApp`, that opens three kinds of document:
a `.docx` as **Writer**, a `.pptx` as **Slides**, an `.xlsx` or `.csv` as
**Sheets**. It is Swift on the Starling SDK (the Flutter framework
ported to Swift, no Dart VM) and runs natively on macOS, in the browser
as WebAssembly, and on iOS (simulator). On Linux and Windows the same
code builds and runs the test gates without a window; windowed apps
there are decided and next (Plan). The public builds are writer.starling.build,
slides.starling.build and sheets.starling.build.

The product promise is the same for each kind: open a file a colleague
sent, change it, send it back, and Word, PowerPoint or Excel opens the
result with nothing lost and nothing moved. Everything since 2026-09-29
has been measured against exactly that, with the real Microsoft apps as
the oracle.

## Status

All three kinds open, edit, save and export to PDF on macOS and in the
browser, and every planned milestone (Writer's Phase 2 and editor
M1–M10, Slides S1–S8, Sheets X1–X5) is done. The work now is fidelity:
how close our drawing of a real file is to Microsoft's, as the share of
differing pixels against Word, PowerPoint and Excel's own PDF of the
same file.

| Kind | Works today | Fidelity against the real app | Not done |
| --- | --- | --- | --- |
| Writer (`.docx`, RTF, Markdown; PDF out) | Paged editing with styles, lists, tables, pictures, headers and footers, fields, find and replace, spelling, IME, navigation pane; Word's pagination hints | Round trip (Word prints original and our saved copy): 176 of 179 within 1%. Our drawing against Word's print: mean 7.38% (130 POI docs 3.44%, 68 Chinese government docs 13.81%) | Lines and pages break elsewhere in the Chinese sample; WMF/EMF pictures only partly wired; no comments or tracked changes |
| Slides (`.pptx`; PDF out) | Canvas editing, layouts and themes, tables, pictures, six chart kinds, SmartArt, preset geometry, WordArt, WMF/EMF, animations, slide show, presenter view | 553 decks against PowerPoint's export: mean 3.01%, 371 at or under 2%, 8 over 20%. Windows build 2.95%; browser build pixel-identical to native on 522 of 553 | Video and audio, morph and motion paths, ink, 3D materials, comments; recent painter work seen only through the PDF export |
| Sheets (`.xlsx`, CSV; PDF out) | Formula engine, 240-odd functions, incremental recalc, dynamic arrays, tables, filters, sort, outlines, conditional formats, validation, charts, protection, printing | 751 workbooks printed against Excel's print: mean 1.93%, median 0.40%, 42 exact | Pivot tables, macros and any scripting, external links, sparklines, slicers; radar, stock and surface charts; iOS and Linux untested |
| Site (a git repository, published static; `docs/plans/site.md`) | `site.json` + `pages/*.json`; `--site-build` makes the folder GitHub Pages serves (app, pages, manifest, search index, a shell page per route with og tags); the reader in a tab reads it, the native app on a clone edits with the whole Writer and publishes with git | Gated: `test/site-build.sh` (the build, a rebuild, a `/demo/` base, an edit), `test/site-web.sh` (headless Chrome reads, moves, searches, under `/` and `/demo/`) | A demo on a real Pages URL; delete/rename/reorder pages; first-load time on Pages |
| Wiki (pages stored as the model; `docs/plans/wiki.md`) | Spaces, page trees, versions with restore, locks, search, .docx import/export, sign-in; the wasm Writer in flow layout is the only renderer, in a tab or natively (`--wiki <url>`) | Gated end to end: `test/wiki-api.sh` (38 checks), `test/wiki-web.sh` (headless Chrome edits and saves), `test/wiki-codec.sh` (327 of 327 readable corpus files round-trip the stored form exactly) | Comments, mentions, permissions beyond sign-in, attachments, real-time co-editing, browser IME; Linux server untested |

Shared: 333 unit tests (one known failure, an Arial line-height
constant); the layout-parity gates pass natively, in the browser and
after a save; the browser build exports the same PDF as the native one.
Composed text input (IME) is not in the browser yet.

## Architecture

Each layer draws only on the one below it. The three kinds share
everything above and below their own four layers.

```
Shared chrome (apps/OfficeApp)   OfficeRoot picks the shell by kind; Ribbon,
                                 Backstage, title row, status bar, find,
                                 colour bars, recovery copy, fonts
┌─ Writer ─────────────┐ ┌─ Slides ──────────────┐ ┌─ Sheets ──────────────┐
│ RichEditable (sdk)   │ │ SlidePainter          │ │ SheetGrid             │
│  RichLayout: pages   │ │  canvas, thumbs, show │ │  painted grid, panes  │
│ RichDocumentController│ │ DeckController        │ │ WorkbookController    │
│  edits, select, undo │ │  mutations, one undo  │ │  CalcEngine, undo     │
│ RichDocument (sdk)   │ │ Deck                  │ │ Workbook              │
│  paragraphs of runs  │ │  slides of shapes     │ │  sheets, sparse cells │
│ Docx.swift           │ │ PptxReader/PptxWriter │ │ Xlsx.swift, Csv.swift │
│  docx, RTF, Markdown │ │  PresentationML       │ │  SpreadsheetML        │
└──────────────────────┘ └───────────────────────┘ └───────────────────────┘
Package layer (apps/OfficeApp)   Zip.swift over zlib; MiniXML, the app's own
                                 XML reader (system parser as fallback);
                                 OfficeFonts; PdfExport; Metafile (WMF/EMF)
Starling SDK (sdk/)              the Flutter framework in Swift, 182k lines;
                                 FlutterSwiftBridge is dart:ui — C++ interop
                                 natively, skwasm exports on the web
Hosts                            FlutterCocoa (macOS) · FlutterWeb (wasm) ·
                                 FlutterUIKit (iOS sim) · GTK / DRM child
                                 (Linux, app next) · FlutterWin32 (app next)
Engine                           the starling-engine fork of Flutter's C core:
                                 Skia (Linux, web), Impeller (Apple), SkPDF,
                                 ICU line breaking, text shaping
```

Each kind's model, controller and file format are plain Swift with no
engine dependency, which is what lets the same code calculate, lay out
and write files on every platform and in the headless command-line
modes the tests use. Three choices shape the rest:

- **One app, not three.** A session carries a document kind;
  `OfficeRoot` mounts `OfficeShell`, `SlidesShell` or `SheetsShell` for
  it, and a file of another kind picked in any shell switches shells
  with the same bytes (`PickedFile`). Each app package compiles its own
  copy of the framework, so one package is also a build-time decision.
- **Writer's editor lives in the SDK**, not the app.
  `sdk/Sources/Flutter/RichText/` (model, controller, incremental
  per-paragraph layout with pagination, `RichEditable`, `KeyChord`) is
  the rich-text stack for every future app; Slides reuses it for text
  in shapes, Sheets for cell editing.
- **Painted, not widget-built.** A page, a slide and a grid are each one
  `CustomPaint` drawn from the model, so the screen, the thumbnails,
  the slide show and the PDF export all go through one painter per
  kind. That is what makes a PDF the test oracle for what the app draws.

## How it is implemented

42k lines of Swift in `apps/OfficeApp/Sources/OfficeApp` (11.3k shared,
14.5k `Slides/`, 16.5k `Sheets/`) plus the 7.8k-line editing stack in
`sdk/Sources/Flutter/RichText/`; the unit tests are another 7.7k.
Branch `office` is the mainline for all of it (the `sheets` worktree
merges into it), with engine changes on starling-engine's `starling`.

| Concern | How | Where |
| --- | --- | --- |
| Reading a package | A zip reader over zlib; parts parsed by the app's own XML reader, the system parser only for non-UTF-8 parts or a `DOCTYPE`; a sheet's rows stream through a callback instead of building a tree | `Zip.swift`, `MiniXML.swift`, `Docx.swift`, `Slides/PptxReader.swift`, `Sheets/Xlsx.swift` |
| What we do not understand | Kept as XML on the model (`opaque` shapes, `kept` sheet parts, `rawFormula`, differential formats) and written back verbatim; the editor touches only what the user changed | each format's reader and writer |
| Inheritance resolved at read time | docx styles (docDefaults → Normal → table style → named style → paragraph), pptx placeholders against layout and master, xlsx cell styles; the model holds absolute values and inherited flags, so a save writes only what changed | `Docx.swift`, `Slides/Deck.swift`, `Sheets/Workbook.swift` |
| Fonts | Files name Word's faces; the app bundles metric-compatible clones (Liberation for Arial, Times and Courier; Carlito for Calibri; Caladea for Cambria; DejaVu for Verdana) and the browser loads the same files, so line breaks agree everywhere | `OfficeFonts.swift`, `Resources/fonts` |
| Formulas | Recursive-descent parser to an AST that prints back to Excel's text; a dependency graph ordered once and kept between edits; volatile functions, dynamic arrays, LET and LAMBDA; unknown functions keep their text and cached value | `Sheets/Formula.swift`, `Calc.swift`, `Functions.swift`, `MoreFunctions.swift` |
| Undo | One `EditOp` with an inverse per mutation, coalesced typing; a text box inside a slide folds its text session into one deck step | each controller |
| PDF and printing | The painter records each page into a `Picture`; the engine's SkPDF backend (compiled in for this fork) writes it with subsetted fonts, natively and in the browser | `PdfExport.swift`, `Sheets/SheetPrint.swift` |
| Platform differences | `#if os(WASI)` fences files, recent lists and the recovery copy; 32-bit `Int` on wasm, so colours are `Int64` literals; no `DateFormatter`; Foundation string methods that do not link on wasm go through `StringHelpers` | throughout; `docs/plans/wasm.md` |
| Command-line modes | `--convert`, `--layout`, `--deck-pdf`, `--sheet-pdf`, `--sheet-layout`, `--xlsx-check`, `--read-bench`, `--bench`, `--landing-deck`: the same code without a window, which is how the gates and sweeps run on every platform | `main.swift`, `ReadBench.swift` |

Rules the code follows, each paid for and recorded in the plan
documents' trap sections: keyboard handling goes through `KeyChord`
because the DRM shell and the windowed hosts number keys differently;
timers use `DispatchQueue.main` with a generation token because
`Foundation.Timer` never fires on the DRM embedder; an interior
`RepaintBoundary` paints nothing in this framework, so thumbnails are
the painter at a smaller scale; and a programmatic text change fires
`onChanged` in this port's text box, so mirrors such as the formula bar
guard against reading their own echo.

## How it is tested

The oracle is the real Microsoft app, not a reference renderer of ours:
Word, PowerPoint and Excel print the file to PDF, our command-line
export prints the same file, and `test/pdf-diff.swift` scores each page
as the share of differing pixels. Two gates come out of that, read
differently. The **round-trip gate** has the real app print both the
original and our saved copy, so the expected score is 0.00 and any
difference is something the writer lost. The **painter gate** scores
our drawing against the real app's, where fonts and anti-aliasing cost
every page a little, so its use is the ranking: the worst files show
what the app does not draw.

| Tier | What it checks | How to run | Last result |
| --- | --- | --- | --- |
| Unit tests | Models, controllers, formats per part, the formula engine against Excel-documented values, undo invertibility, incremental recalc against a full pass | `swift test --package-path apps/OfficeApp` (`test/run.sh --office`) | 333 tests, 1 known failure |
| Layout parity | The same document lays out identically natively, in headless Chrome and after a save: one line of text per laid-out line, diffed | `test/office-layout.sh`, `test/sheets-layout.sh` (in `test/run.sh`) | 0 differing lines |
| Writer round trip | Word prints the original and our saved copy | `test/docx-word-render.sh` (AppleScript drives Word) | 176 of 179 within 1% |
| Writer painter | Our PDF against Word's print, 179 documents (130 Apache POI, 68 Chinese government) | `test/docx-app-render.sh`; `test/docx-web-render.sh` for the browser build | mean 7.38% |
| Slides painter | Our PDF against PowerPoint's export, 553 decks | `test/pptx-app-render.sh`; `OFFICE_WEB=1` for the browser | mean 3.01%; Windows build 2.95% |
| Slides round trip | PowerPoint renders original and saved copy, and reports repairs | `test/pptx-powerpoint-render.sh`, `test/pptx-check.py` | 94 decks re-saved identical through the new XML reader |
| Sheets painter | Our print against Excel's "Entire Workbook" print, 757 PDFs made on Windows over COM | `test/xlsx-app-render.sh`; references from `test/xlsx-excel-render.sh` | mean 1.93%, median 0.40% |
| Sheets acceptance | Excel opens our saved file clean or reports a repair | `test/xlsx-excel.sh` | clean on the fixtures |
| Driven on screen | Scripted clicks, drags and keys into the live app, screenshots a person reads | `test/office-drive.py`, `test/sheets-drive.py`, `OFFICE_SCRIPT=test/scripts/sheets-*.txt` | each milestone, by hand |
| Browser end to end | Open through the picker, type, save as a download, read it back natively | `test/sheets-web.sh`, `build/tools/web-drive.mjs` | passes |

The corpora are checked in under `test/corpus/{docx,pptx,xlsx}` with
the real apps' PDFs and each sweep's per-file scores (`baseline.tsv`,
`roundtrip.tsv`), so a sweep anywhere is comparable with the last; the
larger pools (2,037 Chinese documents, 810 workbooks, 1,118 decks) live
in `~/.cache/starling`. Two rules keep the numbers honest: the real
app's PDFs are made once and reused, because Word prints some originals
differently from one session to the next; and a change is checked on
its own file and then over the whole corpus from a frozen build,
because two Sheets rules that were right for one workbook were wrong
for five others and showed only in a full sweep.

## Performance

A real file opens in about a second and the first screen paints in
under 30 ms; what remains is per-cell memory in Sheets and Writer
laying out every paragraph before its first frame. `OfficeApp
--read-bench`, release build, M1 Pro, 32 GB, 2026-10-13, after the
switch to the app's own XML reader and streamed sheet rows:

| File | Parse | Then | Peak memory |
| --- | --- | --- | --- |
| HowWeRefactor.pptx, 28 slides, 873 shapes | 0.33 s (was 1.0 s) | load and paint slide 1 under 30 ms | |
| Generated deck, 2,000 slides | 1.5 s (was 3.7 s) | | 126 MB |
| bug65649.docx, a real Word document | 1.4 s (was 2.5 s) | | |
| Generated document, 3,386 pages | 1.7 s (was 2.7 s) | full layout 4.4 s before the first frame | 2.9 GB |
| LIBRE_OFFICE-116306-0.xlsx, 663,087 cells | 1.1 s (was 4.4 s) | recalc 1.1 s, first screen under 30 ms | 326 MB (was 693 MB) |
| Generated workbook, 1M cells, a formula per row | 3.0 s (was 9.7 s) | recalc 1.1 s | 0.81 GB (was 1.36 GB) |

Editing was gated earlier and has not moved: a keystroke on a 200-page
document lays out in about 100 µs and paints in about 150 µs; a
30,000-formula workbook recalculates a cell nothing reads in 0.05 ms
and a full pass in 0.14 s. Still expensive: the formula tokenizer is
about a quarter of opening a workbook with a formula per row; Writer
lays out every paragraph before the first frame; a cell costs about
800 bytes and a Word paragraph about 64 KB. Not measured: the browser
build's read performance, and any of this against Word, Excel or
PowerPoint on the same files.

## Plan

The next stretch stays on fidelity, one cause at a time with a full
sweep after each, because that is where the product promise is still
unmet; platforms and scripting come after. In order:

1. **Writer's painter on the Chinese sample** (13.81% against Word, no
   document under 2%): lines and pages break elsewhere, 1,275 pages
   against Word's 1,239. Steered by `docx-line-match.py`, one gap at a
   time, the way the POI documents were brought to 3.44%.
2. **Slides' middle band** (174 decks at 2–20%, two thirds of what is
   left): sample every fifth deck by rank, name a cause from its pair
   image, fix what recurs. Suspects: wrapping a word off through font
   substitution, autofit a step off, percentage spacing, shadows and
   glows. Then see the post-SmartArt work on screen through
   `test/slides-drive.py`, since the export skips the editor's paths
   (a turned cell's caret, metafile fills).
3. **Sheets' leftovers**: the ten workbooks a page apart from Excel;
   radar, stock and surface charts; the row heights not yet understood
   (a Lucida row at 13.32 pt, 52348's rows at 15.94 pt).
4. **Opening large files**: a byte-level formula tokenizer; Writer's
   first frame before the full layout, in `RichLayout.swift`, which
   the Word fidelity work is editing at the same time, so it needs
   coordination; the 800 bytes per cell and 64 KB per paragraph.
5. **Linux and Windows apps** (decided 2026-10-13: a real windowed app
   on each, not only the headless gates). The hosts exist (`FlutterGTK`
   and the shell's DMA-BUF child on Linux, `FlutterWin32` on Windows)
   and OfficeApp already compiles for both. Linux needs the `FluentApp`
   child trap fixed in the SDK, a `registry/catalog.d` record, window
   title and close request on the child socket, file associations from
   Files, and the `.deb`. Windows needs the windowed run checked, file
   dialogs, fonts and a package. Then Sheets on iOS and the Linux desktop
   (untested), a phone layout for iOS, and IME in the browser.
6. **Scripting**, which Sheets has none of today (no `.xlsm`, no VBA,
   no Office Scripts; a defined name holding a `LAMBDA` is the only
   user-defined function). Open `.xlsm` and keep its macro project
   intact on save first; then, if automation is wanted, a JavaScript
   surface of our own over a small workbook API, which needs an engine
   bundled on Linux and Windows. Running existing VBA means an
   interpreter plus Excel's object model and is not planned.

Open decisions:

- A suite name. The bundle is "Writer" and each window names its kind;
  the directory is still `OfficeApp`.
- Which scripting road, if any, from item 6.
- Whether opening times should be compared against Word, Excel and
  PowerPoint on the same files, and whether the browser build's read
  performance is worth measuring now.
- Comments and tracked changes in Writer, which no plan document covers.
