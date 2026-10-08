# Office: a cross-platform document suite on the Starling SDK

Status: **Phase 2 feature list done on macOS** (Writer: docx, PDF, pictures,
headers/footers, tables, named styles, navigation pane), 2026-09-29, branch `office`.
**Name (2026-09-30): the app is "Writer"** in its title bar, launcher and
bundle; "Office" stays only as the package/directory name and, if ever
needed, as "Starling Office" for the suite. Microsoft holds OFFICE and
WORD marks; the bare word in a title bar was the one real exposure. The
ribbon patent family (priority Aug 2004) is expired, most of it with
maintenance fees lapsed; the 2006 design patents expired 2021. The File
tab is a quiet pill, not a brand-coloured block, and third-party notices
ship in the bundle (`Resources/THIRD_PARTY_NOTICES.md`, summarised on
File → Info).
**Next: the editor itself — `office-editor.md`** (cursors, pictures, rich
clipboard, IME, tables, links, ribbon truth), at the user's direction.
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

**Word round, 2026-10-07.** Microsoft Word (16.113, on the Mac, in its
unlicensed read-only mode) is now the .docx acceptance oracle, as
PowerPoint is for Slides: `test/docx-corpus.py` round-trips Apache
POI's 130 Word test documents through `--convert` (read, save, read the
copy again, `test/ooxml-check.py` on the copy — a format-agnostic
package checker new with this round), and `test/docx-word.sh DIR` opens
every copy in Word and reports whether it asks to recover the file.
Before the round: 119 round-tripped, 4 copies read back wrong, 7
originals did not open. After it: 122 round-trip and the 8 refusals are
six fuzzer-truncated zips and two encrypted files; and Word opened every
real copy clean, 121 of 121. What it found:

- **Table cells inside content controls were dropped.** Word wraps a
  row or cell in `w:sdt` for repeating sections and cell controls; the
  row and cell loops saw only direct children. They now see through the
  wrapper (Bug54771a: 6 of 10 paragraphs had come back).
- **5000 nested tables crashed the reader** (deep-table-cell: a stack
  overflow through the cell recursion). Past 32 levels a cell's
  paragraphs are gathered without recursing.
- **An encrypted .docx was read as text** and written back as a copy
  Word could not open at all: a password-protected package sits in an
  OLE container, which starts `D0 CF 11 E0`. Such a file is refused with
  a reason now, as a binary `.doc` is.
- **Every saved file opened in "Compatibility Mode"** — we wrote no
  settings part, so Word laid our files out by its 2007 rules. The
  writer now emits `word/settings.xml` with compatibility mode 15.

Word's read-only mode refuses scripted `save as`, but it still prints,
and the print dialog's PDF menu saves one — so the render comparison
exists after all (next paragraph). Left: Bug54849 re-reads with one
extra empty paragraph in a merged cell (a count nit, not a repair).

**Pixel round, 2026-10-07.** `test/docx-word-render.sh IN OUT WORK`
prints every original and its saved copy to PDF through Word itself
(`test/docx-word-pdf.applescript`: ⌘P, the PDF menu button, "Save as
PDF…", the save panel by keystrokes, because the panel is remote-hosted
and shows no controls), then `test/pdf-diff.swift` renders both with
CoreGraphics and scores each page by the share of pixels that differ,
writing a side-by-side PNG (original | ours | difference) for any page
over 0.5%. Word-vs-Word, so every difference is ours to explain, and
the ranking is what to fix next. Round 1 (105 scored): 20 documents at
0%, 39 under 1%, 21 between 1 and 5%, 25 over 5%, nine of them whole
pages lost (charts, shapes, attached objects, pictures in headers).
What the pictures said, and what changed:

- **The default font and size** (sample.docx, 10.35% → 0.00%): the
  writer's document defaults were Calibri 11 whatever the file said;
  they are now Normal's own font and size, read from the file's
  defaults and Normal.
- **Theme fonts** (heading123, table-alignment, and 78 corpus documents
  that say `minorHAnsi` somewhere): the theme part was dropped, so Word
  fell back to Calibri where the file meant Cambria or Aptos — and the
  taller Aptos lines were the row-height drift the table document kept
  showing. The reader now resolves theme references through the file's
  theme before any font is read, and the theme part rides along in the
  saved file.
- **Custom style chains** (52288): a style's look is its `basedOn`
  chain's; each style had been read alone. Styles the body uses that
  map to none of ours now join the sheet under their own ids.
- **Soft line breaks** (Bug54849's "extra paragraph"): `w:br` had split
  the paragraph; it is a line break inside it now.
- **Footnotes and endnotes** (37 documents have the part; form_footnotes
  at 21%): the reference marks were dropped with the parts. The parts,
  their rels and what those reach are kept verbatim
  (`RichDocument.keptParts`), the mark reads as its number in
  superscript tagged with the note it stands for (`NoteReference`), and
  the writer puts the reference, the parts and the note styles back.
  Only a part that is well-formed is kept — a fuzzer's damaged theme
  made the copy as unopenable as the original.
- **Table alignment, cell shading, table indent, row heights and cell
  margins** (table-alignment 11.9% → 0.24%, table-indent, the form):
  `w:jc` on the table, `w:shd` on cells, `w:tblInd`, `w:trHeight` and
  `w:tblCellMar` now reach the model, the layout and the writer. The
  margins were systematic: the layout padded cells 3pt all round and the
  writer said nothing, so Word applied its own 0/5.4pt to every table.
- **Charts, shapes and embedded objects** (61745 11.8% → 0.00%, bug57031
  100% → 10%, WordWithAttachments 100% → 10%): a drawing that is not a
  picture, a VML picture, an OLE object or a markup-compatibility wrapper
  is an `ImageAttachment` with no decodable bytes — an empty box of its
  extent in the editor — carrying the file's markup verbatim
  (`sourceXML`, every prefix it uses declared on it, including the ones
  an `mc:Choice Requires` names) and the relationships it names
  (`sourceRels`); the read keeps each part and, through its rels,
  everything it reaches, with the content types the file declared
  (`keptPartTypes`); the writer puts it all back under fresh ids.
- **Header and footer distances**: the writer put both 708 twips from the
  page edge whatever the file said; eight copies with small margins made
  Word warn "Your margins are pretty small" at print time (and the alert
  hid behind the save panel, where the script never looked).

Harness lessons: Word raises alerts that block the print — "paper size
… different from the printer", "margins … outside the printable area",
"page borders … outside the printable area", "Your margins are pretty
small", a mail-merge data source that is gone — each handled by the
script now; an unhandled one leaves a modal dialog and every document
after it scores "no document window". Another session driving Excel on
the same Mac steals the save panel's keystrokes. And a recursive walk
over a fuzzer's XML tree overflows the stack where the iterative one
does not (deep-table-cell, again).

After that pass (110 scored; the 11 errors are originals Word itself
refuses — six fuzzer zips and five damaged files — so every copy we write
prints): 25 documents at 0%, 45 under 1%, 20 between 1 and 5%, 20 over
5%. Round 1 was 20 / 39 / 21 / 25 of 105.

**Second pixel round, 2026-10-08.** The ranking again, and what each
picture turned out to mean:

- **Table borders** were drawn on every table; 64 of the corpus's 109
  say nothing about borders and have none, because Normal Table has
  none. Borders resolve from the table, its style's chain, the default
  table style, then none.
- **Over-wide grids** (33 tables; 60329's first column alone is wider
  than its landscape page): Word autofits them to the column, the layout
  now scales them the same way.
- **Line rules**: `exact` and `atLeast` were ignored (Bug51170's "at
  least 1pt" paragraphs took Normal's 1.15 lines). Exact and real
  minimums are `lineHeightPoints` with a new `lineHeightIsMinimum`; a
  tiny minimum is single spacing.
- **Negative indents** (a style hanging into the margin) were written as
  none; a footnote mark lost its own run properties and wrapped
  elsewhere — the boringcrypto layout round trip caught that one.
- **Pictures inline with text** (VariousPictures 100%, issue_51265_3
  40%): every picture had been a paragraph of its own, so a line of three
  became a column of three and the page overflowed. A picture or kept
  object is now a one-character run (U+FFFC) whose style names an entry
  in the paragraph's `inlineImages`; the layout hands the painter a
  placeholder of its size on the baseline (`RichImageSpan`, a concrete
  `PlaceholderSpan` — the port keeps Flutter's assertion that the base
  is abstract — and the new file needed the scratch's plan reset before
  any dependent saw it) and paints the picture into the placeholder's
  box; a paragraph that is one picture alone stays the editor's picture
  paragraph.
- **Tracked changes** (delins 13%): deletions were dropped and
  insertions accepted; what Word prints is the markup. Runs inside
  `w:ins`/`w:del` carry a `RevisionMark`, shown underlined or struck in
  the reviewer's colour, written back as the change they were.
  Formatting-change balloons are not kept.
- **Section breaks** in the body were dropped with their `sectPr`
  (Headers: one page of three); a next-page break is a page break now.

Harness: the Print dialog's PDF menu sometimes needs a second click,
and a miss left the dialog open and the rest of the pass "no document
window" — the script retries three times, then dismisses the dialog. Two
more passes lost half the corpus the same way for a different reason:
the save panel was up and waiting while PowerPoint was frontmost —
another session sweeping decks on the same Mac — so the typed name went
there. The panel is a sheet of the Print window after all, so Save is
clicked through it now and Word is brought to the front before each
keystroke; a 20-page document of pictures also prints for longer than
the 30 s the script waited (120 s now).

After the second round (111 scored; the 11 unscored are originals Word
refuses): 26 documents at 0%, 48 under 1%, 21 between 1 and 5%, 16 over
5% — from 20 / 39 / 21 / 25 of 105 in round 1. Headers 100% → 0.03%,
VariousPictures 100% → 4.4%, shapes-with-text 10.5% → 0.24%, chartex
9.2% → 3.6%, delins 13.3% → 9.5% (the balloons), issue_51265_3 40% →
27.5% (three of its pictures are anchored, still a paragraph each).
Two seemed to go the other way — heading123 0.16% → 4.7%, Bug51170
13.9% → 15.6% — and the first turned out not to be ours at all: the
copy was byte-identical to the first round's, and a fresh print of the
*original* differed from the stored original PDF by 4.70% (Word, in a
new session the next day, substituted its Times differently) while the
copy differed from the fresh original by 0.18%. The driver had been
reusing an original's PDF across days; it now reuses one only if the
same Word session printed it, so both sides always come from one
session. The numbers above are from mixed sessions and are rerun below. Still ranked: multi-section
files whose page counts differ (bib-chernigovka, bug65649, bug59058,
drawing), the form (form_footnotes: checkbox fields, cell merges, row
heights), 60329's ragged table, pictures in headers, heading numbering
defined on a style (3 documents), conditional table-style shading (1),
`w:caps` and paragraph borders (3 each).

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
request per host. Own plan revision. That revision is `docs/plans/slides.md` (2026-09-30).

## One layout everywhere (2026-09-30)

A document lays out the same — every line break, every page — on the
desktop, in the browser, and after our writer has saved it. This is
measured, not assumed, and gated:

- **The measure** is `RichLayout.lineDump`: one line of text per
  laid-out line, `p<page> ¶<paragraph> <height> |<text>|`, with each
  block's height. `OfficeApp --layout file.docx` (or `--layout welcome`)
  prints it natively; `starling.debug('layout')` in the page (the
  `hostDebugQuery` hook, `starling_debug` in `FlutterWeb`) prints the
  same. `diff` the two and one line names the paragraph that broke
  elsewhere.
- **The gates**: `testDocxRoundTripKeepsLayout` (native: the Word
  fixture and its saved copy give the same dump) and
  `test/office-layout.sh` (native vs browser vs saved copy, for the
  welcome page and both fixtures, through headless Chrome via
  `build/tools/web-drive.mjs`; `test/run.sh` runs it and skips without
  Chrome, node, the native binary or `.stage-web-OfficeApp`). Last
  result: 0 differing lines in all five comparisons.

What the measuring found, and the rules that came of it:

- **The page's line breaker adds nothing to ICU.** `Intl.v8BreakIterator`
  is ICU's UAX #14, the same rules the native engine applies. A pass that
  "also broke after every run of spaces" could only add the breaks ICU
  had refused (`encrypt / decrypt` broke before the slash — LB13, no
  break before `/` even after spaces) and made one line of 1,072 wrap
  differently. The page marks an opportunity hard when the segment ends
  in a newline, and that is all.
- **Paragraph spacing is absolute.** `spaceAfter` and `lineSpacing` are
  what the file says and what the layout draws; 0 is no space, not "the
  default". The type's defaults are Word's Normal (8pt, 1.08), `.cell`
  is Table Grid's (0, single), and the readers fill in the file's own
  hierarchy — docx: docDefaults → Normal → the table's style in its
  cells → the named style → the paragraph; RTF: `\pard` is 0 and single
  and Word's RTF spells its `\sa160\sl259` out. Before this, a Word
  Heading 1 (0 after) drew 8pt after, an explicit `line=259` drew
  1.08², a TextEdit file meant for single lines drew 1.08, and the
  Code style's own "0, single" could not be expressed.
- **Writers spell spacing out on every paragraph, rounded.** Before,
  after and line, always, so Word and we agree whatever the file's
  defaults; to whole twips and 240ths, because `Int()` truncation took
  1.08 lines to 258/240 and lower on every save. The old writer's other
  loss was giving cell paragraphs the body's 8pt after: the 26-page
  fixture came back as 30.
- **Fonts are the same faces on every platform** (OfficeFonts, Google
  Docs' model): the file keeps Word's names, the shipped clones draw
  them, and the browser loads the same files. Without this the line
  breaks could not agree.

Still not Word-exact, known: `w:lineRule="exact"`/`"atLeast"` (the
fixture's TOC has 383 exact-height lines; the model has only a
multiple), `contextualSpacing`, `keepNext`/`keepLines`/`widowControl`
pagination, and `basedOn` chains deeper than Normal.

## iOS (2026-09-30)

`build/ios-app.sh OfficeApp` builds, stages `.stage-ios/Office.app` and
(with `--run`) launches it on the simulator; verified on the iPad Pro 13"
simulator against engine `starling` 1848a377952 built as
`ios_debug_sim_arm64` in starling-engine-ios. The welcome document,
ribbon, ruler, status bar, typing and the document fonts all work. On an
iPhone it runs with the desktop layout — the title wraps letter by
letter and the ribbon and page overflow — so a phone needs its own
layout (Word's phone UI is a different product), which is design work.

What it took, neither of them in the app:

- **The first frame.** iOS creates the output surface twice (at layout,
  and again when the scene becomes active); the engine asks the
  framework for a frame after each, and the widgets adapter, which skips
  compositing when nothing is dirty, answered the second with nothing —
  a release build came up black until a key press. An engine-initiated
  frame (one `PlatformDispatcher.frameRequested` did not ask for) now
  composites, on the Darwin hosts (`unsolicitedFramesComposite`).
- **Wrong glyphs in the Fluent chrome** ("Do cument 1" with its m over
  its e, a placeholder as accented capitals) — the same bug the desktop
  hit as "the 14pt menu bug": the bridge dylib's Skia and the engine's
  number typefaces from 1 and the rasterizer keys strikes by (typeface
  ID, size). Fixed in the engine (f920984227d, the bridge's counter
  starts four million up); needs an iOS engine built from `starling` at
  or past it. A day was spent blaming Selawik-Semibold's name table
  before that landed — the theory was wrong, and the workaround (Regular
  only on iOS) is gone.

Traps: `flutter/tools/gn` regenerates with `--check`, which fails on
include violations upstream carries — regenerate with plain
`gn gen out/ios_debug_sim_arm64` (the host builds are made that way).
A release build swallows framework exceptions; run a debug build
(`swift build` without `-c release`, copy the binary and bundles into
the staged .app, re-`codesign --sign -`) to see them. `sips --cropOffset`
goes BEFORE `-c`. Everything else is in the ios-simulator-visual-testing
memory recipe.

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
