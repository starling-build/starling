# Office: a cross-platform document suite on the Starling SDK

Status: **Phase 2 feature list done on macOS** (Writer: docx, PDF, pictures,
headers/footers, tables, named styles, navigation pane), 2026-09-29, branch `office`
(cut from `main` at 97f3c72). What exists:

- `sdk/Sources/Flutter/RichText/` — the editing stack: model, controller
  with undo and a revision counter, incremental per-paragraph layout with
  pagination (`PageSetup`), `KeyChord`, `RichEditable` (paged or
  continuous, app shortcut hook, page info). 19 model tests.
- `apps/OfficeApp` — the Word layout: title row with quick access and
  search, File → Backstage (Home/New/Open/Info/Save/Save As/Export/Print/
  Close over a Fluent file panel), ribbon (Home complete; Insert, Layout,
  View live; Draw/References/Review placeholders), ruler, find/replace
  strip, status bar with page/words/view switcher/zoom slider. Formats:
  RTF (runs, paragraph props, headings, lists, colours, Unicode — round-
  trips through macOS TextEdit), Markdown, plain text; recent files;
  window title follows the document. Liberation fonts bundled. `swift test
  --package-path apps/OfficeApp` runs the format round trips.
  `build/macos-app.sh OfficeApp` assembles a runnable `.app`.
- Measured on the 200-page generated document (`OFFICE_DEMO_PAGES=200
  STARLING_RICHTEXT_PERF=1`): initial layout 200 ms once, then per
  keystroke 45–100 µs layout and ~150 µs paint, drag-select repaints
  ≤ 230 µs. The DRM-shell half of the gate is still to run on the Linux
  box.

Framework bugs found and fixed on the way, both of which affected every
Swift app: on macOS `libswift_bridge.dylib` has its own ICU that never
received `icudtl.dat`, so every wrapped paragraph broke mid-word (engine
79ed5f071e6 exports `InitializeICU`; `CocoaHost` calls it); and
`LeaderLayer` never applied its offset when building the scene, so every
`CompositedTransformTarget` — each Fluent ComboBox and DropDownButton —
painted at the window's origin.

Phase 2 so far: **`.docx` reads and writes** (`Zip.swift` over zlib,
`Docx.swift`: runs, paragraph props, headings via styles.xml, lists via
numbering.xml, hyperlinks, page breaks, section paper size; tables are
flattened and images skipped until the model has them). A package written
by macOS's converter reads back correctly and ours is accepted by it.
`OfficeApp --convert in out` converts between formats without a window.
**PDF export** works as the plan said it would: the engine now builds
Skia's PDF backend and the bridge exports `WritePdf` (engine 63ec018c62c); the
same `RichLayout` that paints pages on screen records each page into a
`Picture`, and `PdfDocument.write` (FlutterSwiftBridge) writes them with
the Liberation faces embedded and subsetted. Backstage → Export → PDF,
or `OfficeApp --convert doc.docx doc.pdf`. **Pictures** are paragraphs
of their own (Insert → Pictures, `.docx` media in and out, drawn through
`drawImageRect` so the PDF has them). **Headers, footers and page
numbers** are one running line each with `{PAGE}`/`{NUMPAGES}` fields,
painted into the margins of every page, in `.docx` and RTF.

**Direction (2026-09-29): macOS only for now.** Linux, Windows and iOS
wait; nothing below should spend time on them until the user says so.
**Tables** are done: a table is a run of cell-tagged paragraphs, so every
edit, selection and format command works unchanged inside one; `RichLayout`
places a row's cells side by side, draws the borders, hit-tests and
paginates a row as one block; Tab/Shift+Tab move between cells; Backspace
never joins across a cell wall. Insert → Table offers preset sizes and,
inside a table, Insert Row Above/Below, Delete Row and Delete Table (each
one undo step). `.docx` tables read and write as `w:tbl` with the grid's
column widths (verified both ways against python-docx), Markdown tables as
GFM pipe tables with alignment and a bold header row, and the PDF has them
because the same layout paints it. Not yet: column insert/delete, merged
cells (a `gridSpan` keeps the columns after it in place but renders in
one), nested tables (flattened into their cell), RTF tables.

**Named styles** are done: a document carries a `RichStyleSheet` (Normal,
Title, Subtitle, Heading 1–6, Quote, Caption, Code — Word's looks), a
paragraph refers to an entry by `named` (or by its `heading` level), and
applying a style copies the entry's paragraph props onto the paragraph
while the layout takes the entry's character defaults under any direct
formatting. Enter at the end of a Title or heading goes to Normal (the
entry's `next`); Quote and Code carry on. The Home tab's Styles group is
four tiles plus a menu of the whole sheet, each drawn in its own look.
`.docx` writes `w:pStyle` and a styles.xml from the sheet, and on read
takes the file's own definitions for the styles it maps (Word's Heading 1
is 14pt in its 2007 template, ours 20pt — the file wins, verified against
python-docx both ways); RTF names them in the stylesheet and reads names
back (Word's numbering 1–6 as the fallback); Markdown maps Quote to `> `
and Code to a fence, and Title/Subtitle/Caption are plain text there. Not
yet: modifying a style, "update to match selection", themed fonts/colours
from `theme1.xml`.

**Navigation pane** (View → Show): the outline — Title and Heading 1–3,
nested — with the heading the caret is under highlighted; a click moves
the caret there and the editable scrolls it into view. That closes the
Phase 2 feature list.

**Outside writers.** The first real Microsoft Word document — BoringCrypto's
FIPS security policy, 25 pages, 15 tables with merged cells, a table of
contents, captions, numbered headings, shipped in the engine tree under
`third_party/boringssl` and now a fixture (`word-boringcrypto.docx`) — read
whole, wrote back whole, and exported to PDF in a quarter second. It
exposed one model gap: Word numbers per list across the document, with
multi-level labels ("3.1"), and ours numbered every run from 1. A
paragraph now carries its list id, the document keeps each list's level
formats (`lvlText`/`numFmt`), `RichListNumbering` labels the whole
document by Word's rules, and the writer gives every list — and every
anonymous run — a numId of its own, so two separate lists no longer merge
in Word. Google Docs and LibreOffice files are still to be checked
(neither is on this Mac; Pages is, but its AppleScript has no styles and
the screen was locked before it could export). The Text Editor catalog
change waits for Phase 3.

Open, noted: a Fluent menu item whose text style is exactly 14pt draws
stretched letter spacing (13 and 13.6 are fine; the same 14pt Heading 3
in the document is fine), so the gallery menu caps its previews at 13.

Three more framework bugs fell out of the first drop-down ever opened in
a debug build: `RenderFollowerLayer` held its layer by a bare reference,
so the parent's next repaint disposed it and the paint after that
asserted; an `OverlayEntry` removed by a `Tooltip` unmounting during
`finalizeTree` called `setState` while the tree was locked (deferred now
via `BuildOwner.runWhenUnlocked`, standing in for the post-frame callback
upstream uses); and `FollowerLayer` is a stub that applies no transform,
so every flyout painted at the overlay's origin at full width — the
flyout now positions itself from the target's render box through a
`CustomSingleChildLayout`, as fluent_ui does, and a `FlyoutScope` lets a
menu item close the flyout it is in (there is no route to pop).

Not done from the Phase 1 list: the `_writer_session` functional test
(Linux desktop, Phase 3). Three directions from the user shape the plan:
the app is **cross-platform and built on macOS first**, its UI is
**Fluent**, and its layout **copies Microsoft Office**. Decisions marked
**[decide]** were taken with the plan's defaults (one package, `.docx`,
Text Editor stays, name Office).

## Why

The Text Editor (`apps/TextEditorApp`, 1.6k lines) is a plain-text editor
with a paragraph-granular RTF mode bolted on: one align/bold/italic/
underline triple *per paragraph*, one font size *per document*. It cannot
bold a word, has no undo, no find, no lists, tables or images, no scroll
view, one document per process, and its key handling speaks only X11
keysyms, so its chords are dead on every host but the DRM shell. It is the
right thing for `.txt` and code and the wrong starting point for documents.
It stays as the plain-text editor; Office is a new app.

The SDK, surveyed for this plan, splits cleanly:

- **Layout and painting are complete and engine-backed.** `TextPainter`
  has the whole metrics API (`getBoxesForSelection`, `getPositionForOffset`,
  `getOffsetForCaret`, `computeLineMetrics`, word/line boundaries), `TextSpan`
  trees reach the engine's `ParagraphBuilder` with per-run styles, `Canvas`/
  `Picture`/`Image`/`Shader` are full bindings, `RenderTable` is real and
  tested, slivers and `Scrollable` work, and Fluent has the ribbon-shaped
  controls already: `CommandBar`, `MenuBar`, `TabView`, `ComboBox`,
  `NumberBox`, `ColorPicker`, `Flyout`/`MenuFlyout`, `ContentDialog`,
  `Slider`, `Scrollbar`, `TreeView`, and the `FluentSystemIcons` set.
- **Editing does not exist.** No `EditableText`, `TextField`, `SelectableText`
  or IME; `RenderEditable` is a 2.6k-line port nothing instantiates; the only
  text field (`FluentTextBox`) draws its caret as a literal `|` character and
  has no selection. No `Focus` scopes (one global node), no
  `Shortcuts`/`Actions`, no modifier bits in `KeyData`, no
  `LayoutBuilder`/`MediaQuery`, no 2D viewport, no mouse cursors, plain-text
  clipboard only, and `sendPlatformMessage` is a stub.

So the real product of this work is **a rich-text editing stack in `sdk/`**,
with Office as its first customer. That is where the leverage is: the
moment `RichEditable` exists, `TextBox`, `MacosTextField` and every future
app's text input can be rebuilt on it, on every host at once.

## Product shape

**Cross-platform, macOS first.** The SDK has four windowed hosts
(`FlutterCocoa`, `FlutterGTK`, `FlutterWin32`, `FlutterUIKit`) plus the DRM
desktop, and the Terminal app already ships as a macOS `.app` through
`build/macos-app.sh`. Office follows that route: the dev loop on this Mac
is `swift build --package-path apps/OfficeApp` (the binary's rpaths point
into the engine checkout, `engine/src/out/host_debug_arm64`) and the
shippable bundle is `build/macos-app.sh OfficeApp --run`. Linux as a shell
child, Windows through `sdk/tools/build-windows.ps1`, and iOS come after
Writer works on macOS; each is a phase with its own known blockers below,
not a port at the end.

**Fluent style, Office layout.** The root is `FluentApp`; every control is
the Fluent one. This is a deliberate exception to the standing direction
that apps are macOS-styled. That rule exists for one reason, recorded at
`apps/FileExplorerApp/.../main.swift:14`: `FluentApp`'s scaffold traps on
mount as a DMA-BUF child (a `RenderObjectElement` insert cast). It does not
bite on the Cocoa host, and the Linux phase fixes the trap in the framework
rather than working around it, because a Fluent app that cannot run on the
Fluent-styled desktop is the framework's bug. `CLAUDE.md`'s "a Fluent widget
in `apps/` is a bug" line gets amended when that lands.

**One package, `apps/OfficeApp`, three document kinds** (Writer, Sheets,
Slides), opened by file extension or from the Backstage start page.
**[decide]** — the alternative is three apps. One package wins on the
constraints we have: each app package compiles its own copy of the
framework (~100 s), the Linux shell launches first-party apps
single-instance (`_launchOrFocusApp` focuses an existing window rather than
starting a second), the catalog has no `Args=` key, and a macOS `.app` per
kind triples the bundle. The shared chrome (ribbon, Backstage, tabs, undo,
zoom, find, export) is most of the app anyway. **Writer ships first**;
Sheets and Slides are outlined at the end and get their own plan revisions.

**Formats.** Native save is **`.docx`** **[decide]** — it is what people
will hand the app, and ODT costs the same (both are zip + XML) for a smaller
audience. Phase 1 reaches `.docx` through a bridge: RTF with character runs
(the editor's `EditorRtf.swift` is the seed) plus Markdown import/export,
neither needing zip. Phase 2 adds the zip layer (zlib, a ~300-line Swift
reader/writer; no precedent in-tree) and the WordprocessingML subset.
**PDF export** goes through the engine: Skia's `SkPDF` backend is in the
tree but compiled out on every host (`engine/src/flutter/tools/gn:494`,
`skia_enable_pdf = False`). It is renderer-independent (the Linux DRM
embedder runs Skia, the macOS framework runs Impeller; SkPDF needs neither
GPU path), so one C export that takes a recorded `Picture` per page means
the code that paints a page on screen writes the PDF, with real font
embedding, on every host. That is an engine change (both repos, mainline to
mainline) and gets a spike before Phase 2 commits to it; the fallback is a
minimal in-app PDF writer, which loses text extraction unless we also embed
fonts by hand.

**Fonts.** The engine has **no system font fallback** on Linux: a glyph in
a family we did not load paints nothing (`TerminalView.swift:117`). Office
bundles its families as SwiftPM resources and the font menu lists those:
Liberation Sans/Serif/Mono (metric-compatible with Arial/Times/Courier, so
`.docx` files from Word reflow correctly) plus Noto Sans/Serif. CJK and
emoji follow the terminal's precedent and register the system Noto files
*by path* when present (`TerminalView.swift:115-121`). Two traps already
paid for: `Bundle.module` hardcodes the build directory, so the bundle must
be searched for the way `TerminalView.swift:145` does, and `macos-app.sh`
copies `FlutterSwift_*.bundle` into `Resources/`.

## Layout, copied from Office

Top to bottom, the Word window:

1. **Title bar row**: quick-access toolbar (AutoSave toggle, Save, Undo,
   Redo), document name, search box, account/share placeholders. On
   macOS the native title bar carries the document name; the SDK's Cocoa
   host sets the title only at boot (`CocoaHost.swift:37`), so a runtime
   `setTitle` is a small host addition.
2. **Ribbon**: a `TabView` strip (File, Home, Insert, Draw, Layout,
   References, Review, View) over a `CommandBar` per tab, grouped with
   labelled dividers: Home = Clipboard / Font / Paragraph / Styles /
   Editing; Insert = Pages / Tables / Illustrations / Links / Header &
   Footer / Text / Symbols; Layout = Page Setup / Paragraph / Arrange.
   Font group is `ComboBox` family + `NumberBox` size + toggle buttons +
   `ColorPicker` flyouts; Styles is a gallery of `RichEditable` previews.
   Collapsible to tab labels only, as Office does.
3. **File** is Backstage: a full-window page with a left nav (Home, New,
   Open, Info, Save, Save As, Export, Print, Close) and recent files; New
   offers Writer/Sheets/Slides templates.
4. **Document area**: horizontal ruler with margin and indent stops, then
   the page canvas (grey backdrop, white pages with shadow) inside the
   scroll view; optional navigation pane on the left (headings, pages,
   results) and a comments/track-changes rail on the right later.
5. **Status bar**: page n of m, word count, language, then view switcher
   (Print Layout / Web Layout / Read Mode) and a zoom `Slider` with
   percentage.

Sheets swaps 4 for a formula bar plus the grid with frozen row/column
headers and a sheet-tab strip; Slides swaps it for a thumbnail pane, the
slide canvas and a notes pane. The ribbon and Backstage are shared, with
per-kind tabs (Formulas, Data; Transitions, Animations, Slide Show).

## Architecture

```
sdk/Sources/Flutter/RichText/        NEW — the editing stack, app- and host-agnostic
  RichDocument.swift                 paragraphs × character runs × block elements
  RichDocumentController.swift       edits, selection, undo/redo, change notifications
  RichLayout.swift                   per-paragraph TextPainter cache, incremental, pagination
  RichEditable.swift                 the widget: paint, hit-test, keys, caret, scroll, IME caret
  KeyChord.swift                     modifier tracking + X11 keysym / logical-key normalisation
sdk/Sources/Flutter/Widgets/
  Table.swift                        thin widget over the existing RenderTable
  FocusScope (extend FocusManagerStubs) multiple focusable nodes, click-to-focus
sdk/Examples/RichTextDemo/           the twenty-line "an editor is a widget" demo + perf harness
apps/OfficeApp/                      chrome only: ribbon, Backstage, tabs, status bar, formats
  Sources/OfficeApp/
    main.swift                       FluentApp root; theme from the host (dark/light)
    OfficeShell.swift                title row, ribbon, status bar, document tabs
    Ribbon/                          one file per ribbon tab
    Backstage.swift
    Writer/WriterView.swift          ruler + page canvas around RichEditable
    Formats/{Rtf,Markdown,Docx,Pdf}.swift
  Resources/fonts/
registry/catalog.d/office.app        Linux desktop entry (Phase 3)
build/macos/Office.icns
```

### Document model (`RichDocument`)

An array of blocks. A paragraph block is `String` + `[Run]` where a run is a
UTF-16 length and a `CharStyle` (bold, italic, underline, strikethrough,
family, size, colour, highlight, link, superscript/subscript), plus
`ParagraphStyle` (alignment, indents, spacing, list kind + level, named
style / heading level, page-break-before). Non-paragraph blocks: table
(rows of cells, each cell a nested block list), image (bytes + display
size), page break. Offsets are UTF-16 internally because that is what
`TextPainter` speaks; the controller converts at the edge to grapheme-aware
cursor motion the way `EditorBuffer` does today. Simple arrays, not a rope:
a 300-page document is a few thousand paragraphs, and relayout is
per-paragraph.

Every mutation is an `EditOp` with an inverse; the controller keeps
undo/redo stacks and coalesces consecutive typing into one op. The model is
pure Swift with no engine dependency, so it is unit-tested in `test/run.sh`
(0.4 s tier, no GPU, runs on the Mac) — round-trips, undo invertibility,
run splitting and merging, list renumbering.

### Layout (`RichLayout`)

One `TextPainter` per paragraph, built from the runs as a `TextSpan` tree,
cached and invalidated per paragraph by the controller's change set. Today's
editor relays out every paragraph on every keystroke and its painter
`shouldRepaint`s unconditionally; the whole point of the cache is that a
keystroke costs one paragraph. Pagination is a second pass over line
metrics: page size, margins, widow/orphan control, headers/footers.
Tables lay out their cells recursively with the same machinery, not through
`RenderTable`, because a document table has to paginate and hit-test as
text. `LayoutBuilder` does not exist; the page width comes from the
`Scrollable`'s viewport via `MeasureSize`, as `TerminalView` does.

### Widget (`RichEditable`)

`CustomPaint` under a `Scrollable` with a `ScrollController` and the Fluent
`Scrollbar`. Caret, selection rects and cursor blink are painted, not
widgets. Pointer: click to place, drag to select, double/triple click for
word/paragraph (manual detection — registering `onDoubleTap` kills tap on
DRM). Keyboard: raw `KeyData` through `KeyChord`, which tracks modifier
down/up itself (no modifier mask in `KeyData`) and accepts **both** X11
keysyms (the DRM shell) and Flutter logical key ids (Cocoa/GTK/Win32) —
`FluentTextBox.swift:253-283` has the table. Cmd on macOS and Ctrl
elsewhere map to the same chord names. Clipboard through `Clipboard`, which
already has a provider per host (`NSPasteboard`, GTK, Win32, Wayland);
plain text only today, so styled copy within the app goes through an
in-process side channel until the clipboard grows an HTML flavour. IME:
composing text needs a real text-input channel on every host and is a
Phase 3 item; on Linux the caret rect is reported with `sendCaret` so the
shell docks its candidate panel.

### File dialogs

`MacosFilePanelOverlay` is a pure-Flutter panel in the SDK and works on
every host, but under a Fluent app it is the wrong look and on macOS the
user expects `NSOpenPanel`. Phase 1 uses a Fluent-styled in-app panel
(same `FileManager` listing, `ContentDialog` chrome); native panels per
host are a later host-injection closure like `Clipboard.provider`.

### Linux desktop integration (Phase 3, all small shell changes)

- **The `FluentApp` child trap** gets fixed in `sdk/`, not routed around.
- **Window title.** A DMA-BUF child has no title channel; add `sendTitle`
  beside `sendCaret` on the child socket.
- **Close request.** The shell closes a child with `SIGTERM`
  (`LinuxProcessAppManager.swift:1185`). An unsaved-changes prompt needs a
  close *request* the app can veto, with the kill as the timeout fallback.
- **Opening files.** Files' double-click only navigates directories; no
  first-party app is ever handed a path by the desktop. Add an `Opens=`
  key to catalog records, a child→shell `open` message from Files, and
  `_launchOrFocusApp(id, extraArgs: [path])` plus a "reopen with path"
  message for the already-running case. On macOS the same association is
  `CFBundleDocumentTypes` in the `.app`'s Info.plist from `macos-app.sh`.

## Phases

**Phase 0 — the editing stack (spike, gate before anything else).**
`RichDocument` + controller + undo, `RichLayout` with the per-paragraph
cache, `RichEditable` with selection and chords on both key numberings,
`KeyChord`, `FocusScope`, and `RichTextDemo` running on the Cocoa host.
Gate: typing and selection-drag stay under frame budget in a 200-page
generated document on this Mac at 2x, and the same demo runs unchanged on
the DRM shell (not a child; the shell's own host, as the terminal demo
does). Model tests in the fast tier. This is the phase that can fail, and
it should fail early.

**Phase 1 — Writer on macOS.** `apps/OfficeApp` with the Office layout
above: title row, ribbon (Home/Insert/Layout/View populated, the rest
stubbed), Backstage, ruler, paged canvas, status bar with zoom; bundled
fonts; RTF round-trip with character runs; Markdown in/out; find/replace;
word count; `.app` via `macos-app.sh` with an icon; Cocoa `setTitle`.
Driven for screenshots with the osascript recipe already used for the
macOS terminal.

**Phase 2 — Documents people actually have.** Named styles and headings,
lists, tables, images (insert from the panel; paste needs a rich clipboard,
later), headers/footers/page numbers, page setup, navigation pane. `.docx`
read and write (zip layer + WordprocessingML subset, tested against files
from Word, Google Docs and LibreOffice). PDF export via the engine `SkPDF`
export (spike first; both repos, every host's engine build). Text Editor
drops its RTF mode and its catalog copy stops claiming syntax highlighting.

**Phase 3 — Linux desktop and Windows.** Fix the `FluentApp` child trap;
`registry/catalog.d/office.app`; `sendTitle`, close request, file
associations and Files double-click; the `.deb`; a `_writer_session`
functional test beside `_editor_session`. Windows through
`build-windows.ps1` (its cold-build loop is documented in `CLAUDE.md`).
IME composing text and the HTML clipboard flavour on all hosts; I-beam and
resize cursors (no host sets a native cursor today).

**Phase 4 — Sheets.** 2D viewport painted the way `TerminalGridPainter`
paints (glyph atlas, one `drawRawAtlas` per frame), frozen headers, cell
model with a formula engine (parser, dependency graph, a few hundred
functions), `RichEditable` as the in-cell and formula-bar editor, CSV and
`.xlsx` (same zip layer). Own plan revision.

**Phase 5 — Slides.** Canvas of positioned `RichEditable` boxes, shapes,
images, thumbnails, presenter view; `.pptx`; presenting needs a fullscreen
request per host. Own plan revision.

## Traps already known

- **Two key numberings.** The DRM shell delivers X11 keysyms, every
  windowed host delivers Flutter logical key ids, and `KeyData` carries no
  modifier mask. Anything keyboard-shaped is written against `KeyChord`
  from day one; the Text Editor is the example of not doing that.
- **`Bundle.module` hardcodes the build path.** Fonts are found by
  searching for the resource bundle (`TerminalView.swift:145`), or the
  shipped `.app` runs only on the machine that built it.
- **`.build-shared` is the only scratch the Linux desktop stages.** On
  macOS the package's own `.build` is the binary that runs; on Linux it is
  invisible. Adding files under `sdk/` is the worst case for stale
  incremental state — clear `release.yaml`/`build.db` when a new SDK symbol
  "does not exist".
- **Ported widget inits need matching trailing-closure overloads** in
  `Widgets/ResultBuilders.swift`; `test/lint.py` fails on drift. Applies to
  `RichEditable` and `Table`.
- **No `Foundation.Timer` on the DRM embedder.** Caret blink and typing
  coalescing use `DispatchQueue.main.asyncAfter` with a generation token,
  so the same code runs on every host.
- **Registering `onDoubleTap` kills tap on DRM**; double/triple click is a
  timestamp streak inside `onTap`, as in the editor and Files.
- **`FluentApp` traps as a DMA-BUF child.** Known, deferred to Phase 3,
  fixed in the framework.
- **Tabs.** The editor rewrites every `\t` to four spaces on load; the new
  model keeps characters as they are.

## Open questions for the user

1. One suite package (`office`) with Writer/Sheets/Slides inside, or three
   apps? Plan assumes one.
2. Native format `.docx` (plan) vs `.odt` vs staying with RTF.
3. Text Editor's future: keep as the plain-text/code editor and hand `.rtf`
   to Office once Phase 2 lands (plan), or fold it in.
4. Name. `Office` is the placeholder for the suite; Writer/Sheets/Slides
   for the kinds.
