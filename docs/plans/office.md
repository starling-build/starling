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

**Third pixel round, 2026-10-08, one Word session.** The rerun was
driven with both sides printed by one Word session (the first pass of
it wedged at the 26th document: a stray keystroke from the other
session's PowerPoint sweep had opened the Wi-Fi menu over the Print
dialog's go-to-folder sheet, and 63 documents in a row were "no
document window" — the screenshot, not the log, said so). Fixed by
rank while it ran, each from its pair picture:

- **All caps, Small caps, paragraph borders** (`w:caps`, `w:smallCaps`,
  `w:pBdr`; bug65649 alone has 102 bottom rules): `CharStyle.caps`/
  `smallCaps` shown as capitals (small caps at 80%, the UTF-16 count
  kept so offsets still map), `RichParagraphStyle.borders` reserving
  the line and its gap and painting it. capitalized.docx 0%.
- **Borders and margins the cells carry** (bug65649's 5,734-cell table,
  bug59058, table-indent, 60329, bib-chernigovka — HTML-converted
  tables say `w:tcBorders`/`w:tcMar` per cell and nothing on the
  table): more than half the cells decide, with their colour; border
  colours (`TableStyle.borderColor`) are read and written now, every
  table border had been the theme's grey.
- **Header and footer thirds**: `w:tab`, `w:ptab` and the Header/Footer
  tab stops; eleven documents' "name <tab> Page N" had come back run
  together and centred. A paragraph's own `w:tabs` are tab STOPS spelled
  `w:tab` too, and were being read as typed tabs.
- **Deleted paragraph marks** (delins 9%): `w:pPr/w:rPr/w:del` is kept
  (`markRevision`), else Word prints an empty bullet per struck line.
- **Numbered heading styles, colour auto, conditional table parts**
  (65099): a style's own `numPr` numbers its paragraphs ("1.1.1
  Acronyms"); `w:color auto` clears an inherited colour (it was kept);
  a table style's `firstRow`/`band1Horz`/`band2Horz` fills and the
  first row's run look land on the cells, as `w:tblLook` switches them.
- **A file's list ids are kept** (60316's ">" bullets had come back as
  "1." under a renumbered id inside a kept text box); explicit left
  alignment under a centred style is written (bug-paragraph-alignment);
  a footer text box is read from its `mc:Choice` alone ("Page 1Page 1").
- **Form checkboxes, tab stops, 10pt, the border majority**
  (form_footnotes): FORMCHECKBOX fields have no result text and had
  vanished — a box glyph now; `w:tabs` round-trip; a file that states
  no size anywhere is 10pt in Word, not 11; borders from cells need
  more than half of them.
- **Headers and footers with pictures, tables or text boxes, and the
  first-page ones** (Bug51170's logo, 60329's banner, issue_51265_2/3,
  headerPic; four files with `w:titlePg`): kept whole with their
  relationships (`keptHeaderFooters`), referenced from the section again
  unless the editor's header text changed — then regenerated under a
  name no kept part uses. The header text reader walks into tables and
  text boxes too.
- **Indents of zero that unset a style's** (IllustrativeCases: Body Text
  Indent hangs 0.75in into the margin, every paragraph says left 0; the
  writer wrote only non-zero indents, so the body ran 0.75in wide and
  the tables' first column was clipped).
- **Right-to-left paragraphs** (rtl.docx): `w:bidi`, in styles too;
  the layout runs such a paragraph from the right.
- **A floating picture's anchor** (WithGIF's text flowed over its
  picture, VariousPictures, issue_51265_3): `wp:anchor` is kept as
  written and saved verbatim like a chart's, while the editor decodes
  the picture and shows it in the line.
- **A paragraph that ends with its page break** (SampleDoc) was split
  into the part before and an empty part after, and that empty
  paragraph began the next page a line down; the remainder is dropped.
- **An empty paragraph's height IS its mark's font** — the 2026-10-08
  probe said otherwise (4pt and 28pt marks on empty paragraphs, scored
  by pdf-diff) and was wrong; a 2026-10-09 probe with 30 empty
  paragraphs of 28pt marks lands the next line on page two in every
  spelling of `w:pPr/w:rPr`. The commit that wrote the marks was
  reverted on the wrong probe's word and reapplied the next day; it
  took Bug51170 from 10.1% to 0.01%. Make a layout probe a page-count
  test, not a score: a score moves for other reasons.
- **Every section's page setup, and the compatibility mode**: bug65649
  has 15 sections, some landscape, and every page came out portrait at
  the last section's margins — a paragraph that ends a section keeps
  its `w:sectPr` (minus header/footer references) and writes it back,
  the layout still showing one page size. And 32 of the corpus's files
  are in compatibility mode 12 or 14 (52 more state none), whose line
  breaking and table spacing differ from 15's: the settings' `w:compat`
  block is kept and written in place of ours — the EMPTY block too,
  which is Word's legacy (2003) mode: 39 corpus files are in it, and
  drawing.docx wrapped tighter under mode 15, two lines ahead by page
  seven (13% to 1.4% with the empty block put back; an earlier reading
  had dropped it over a form_footnotes page that was a knife edge).
- **A run's explicit off** under a style that turns bold, italic, caps,
  underline or strike on (drawing.docx's `b w:val=0` runs under a bold
  heading 3 came back bold) is written, like indents and alignment.
  The editor still shows such a run bold: `CharStyle` has no
  "explicitly off" — a tri-state is the fix, not taken yet.
- **Body picture names** skipped past a kept part's: a kept header's
  media/image1.png was dropped for the body's own image1.png and
  issue_51265_3's header showed the wrong picture.

Not taken, seen: nested tables (60329's body is a table inside a
table's cell; the reader flattens it, so its boxes and widths go),
bug59058's mid-document drift of half a page over 52 pages, Word's
own font substitution for fonts the Mac lacks (Perpetua, Albertus,
Liberation Serif) — the same on both sides, so not ours.

After the third round (111 scored, both sides of every document from
one Word session; the 11 unscored are originals Word refuses): **35
documents at 0%, 48 under 1%, 15 between 1 and 5%, 13 over 5%** — from
26 / 52 / 17 / 16 (round 2, mixed sessions) and 20 / 43 / 18 / 24
(round 1). Movers: issue_51265_3 27.5% → 18.8%, bug65649 31.2% → 23.8%
(226 → 199 pages against 177), drawing 27.1% → 20.7%, issue_51265_2
8.3% → 3.3%, WithGIF 4.9% → 0.07%, heading123 4.7% → 0.15%,
bug-paragraph-alignment 3.6% → 0.4%, chartex 3.1% → 0.0%, 65099 7.8% →
5.1%, bug57031 6.4% → 4.6%. One went the other way: table-indent 5.1% →
7.2% (LibreOffice's file: Liberation Serif, which Word substitutes).
Still over 5%, in order: bib-chernigovka 28.8% (text-box title, page
count), bug65649 23.8%, drawing 20.7% (nested tables, hidden text),
bug59058 18.9% (half a page of drift over 54 pages), issue_51265_3
18.8% (floated pictures' exact positions), 60329 15.0% (nested
tables), form_footnotes 13.4%, Bug51170 10.5%, IllustrativeCases 9.0%,
delins 8.5% (comment balloons), table-indent 7.2%, WordWithAttachments
6.0% (comments, which scale the page), 65099 5.1%.

**Fourth round, 2026-10-09 to 10-11.** Found from the round-three
pairs, all Word-free until the rerun: the styles a kept header names
and Normal's spacing as the document default (issue_51265_3's header
grew by Word's 8pt after); hidden text (`w:vanish`); comments kept
whole with their ranges (Word's balloons scale the page: four files);
a table's preferred width (`w:tblW` pct/dxa — bug65649's tables came
back narrower); a cell paragraph's style chain laid over the table
style's base (every cell row a point too tall: 65099,
IllustrativeCases, table-indent); auto spacing written off under an
auto-spaced style; a small "at least" line minimum kept as written
(Bug51170 held one paragraph less per page); keepNext, keepLines,
widow control and cantSplit rows; table border widths (sz 6 for most
of the corpus, sz 4 written before); nested tables kept verbatim with
their text flattened into the outer cell for the editor and the
markup written back while that text stands (60329, drawing,
bug65738); a table's fixed layout and cell spacing; paragraph shading
and contextual spacing. A lesson in passing: reverting a
commit by slicing its test out between two anchors took the three
tests added after it with it; they came back from the commit before
the revert.

Where the round ended, with both sides printed in one Word session:
124 scored, 104 within 1%, 10 within 5%, 5 within 15%, 5 above (round
three: 111 scored, 35/48/15/13). The second half of the round was
bisection work — swap one part of the original into our package,
print, repeat — and each bisection ended in a rule Word follows that we
did not: a style with no `w:styleId` and no `w:type` is a paragraph
style looked up by its NAME (60329's 1pt `EmptyCellLayoutStyle` in
every empty cell: 36.6% and four pages to 15.4% and three); a grid is
as wide as its cells REACH, span included, and a row may be shorter
than the grid (bug65649's 63-column estimate table had come back as 62
equal columns, 34 pages longer); a list paragraph's own `w:ind
w:left` sits above its level's (bug65649's appendix clauses started
two-thirds across the page); table and cell borders are per SIDE
(`BorderEdges`: a form ruled outside but not between its cells, a
title cell with a bottom rule alone, heading cells with none inside a
ruled table); a section's `w:pgBorders` is kept (bib-chernigovka's art
frame on 16 pages); an empty header or footer part still reserves its
height; and an empty paragraph IS as tall as its mark's font — the
2026-10-08 probe was wrong, see the trap above (Bug51170 10.1% to
0.01%). bug65649 went 29.4% and 211 pages to 16.2% and 184 against the
original's 177. Two late finds: a table's border LINE STYLE
(`outset`, `double`, ... kept as written) and the document background
(`w:background` — never printed, yet Word lays a document with one out
18pt lower; found by swapping the original's document part in, 0.00%,
then removing only the background, 19%). form_footnotes had fit its
last box on page one by a point where Word's original breaks before
it — the footnote block, the empty footer, the per-side borders and
finally the line styles each closed part of that point: 46% to 13%.
bib-chernigovka 23% to 7%. Then the largest single find of the round:
an EMPTY `w:compat` is Word's legacy layout mode and 39 corpus files
are in it; writing the empty block back took drawing from 13% to 1.4%
(it had wrapped tighter under mode 15, two lines ahead by page seven)
and moved issue_51265_3 10.4 to 9.1, WordWithAttachments 0.9 to 0.4,
with delins the one loser (8.5 to 9.2). After that: a run's character
style (`w:rStyle`, ignored before), the file's own style ids defined
as aliases for kept markup, several repeating header rows, a hidden
paragraph mark, file-named fonts written as named (Liberation Serif
is not Times New Roman's line height), LibreOffice's `w:start`/`w:end`
border sides. And 60329's last 15% was one attribute: landscape
dimensions with no `w:orient` print, in Word, onto portrait paper with
the sides clipped; we added the attribute and printed the page whole.
The writer now adds it only where the file had it (`PageSetup.
orientStated`) — the original document part in our package had
already printed at 0.00%, which is the bisection's cleanest verdict:
when that happens the body writer is the whole story. Three more
after it: a table's border width is the width MOST of its cells draw,
not the first cell's (bug65649's headings were sz 12, its rows sz 6);
a form checkbox goes back as the field, not a glyph in a fallback font;
and the paragraph MARK's run properties are written on every paragraph
that had them — Word sets a list paragraph's number in them and sizes
a last line by them, and IllustrativeCases, which had been a "knife
edge" at 7.6%, went to 0.11% with nothing else changed (drawing 1.4 to
0.7). A kept next-page section break followed by our own pageBreakBefore
had given bug65649 an empty page. And cells that state no width
(`w:tcW` auto) autofit in Word: our grid widths written as their
preferences froze bib-chernigovka's number column and wrapped its text
column a line early — 7.3% to 0.13% (`TableStyle.autoCellWidths`).
Then Word's default table style, which the styles part now always
carries: without it Word in its legacy mode set form_footnotes' tables
5pt to the right, and fourteen files moved down with it (65099 1.35%
to 0.10, Bug60337 0.52 to 0.00). A table's sides keep their own line
style and width (double outside, single between). form_footnotes'
rows then match Word's to two points — which puts its last box back on
page one by those two points, where Word's original breaks before it:
44%, a knife edge and not the rows. Two more: an inline picture's
markup is kept verbatim until the editor resizes it (its effectExtent
decided where issue_51265_3's row of four pictures wrapped: 9.1% to
4.2%, VariousPictures to 0.00); and a list paragraph read from a file
keeps the style the file gave it, none included — we had given every
one List Paragraph, and Word's contextual spacing, which suppresses
space only between paragraphs of the SAME style, then stopped
suppressing it before the plain paragraph after each numbered heading
(bug59058 7.7% to 1.2%, delins 9.2 to 4.7). At that point: 111
scored, 100 within 1%, 8 within 5%, 2 within 15% (bug65649 12.8%,
table-indent 6.9%), and form_footnotes on its knife edge at 44%. Then
a table ruled through its cells, with nothing at the table level (every
HTML conversion), gets no table-level borders back — we had written the
cell-majority verdict as w:tblBorders with inside rules on top of the
cells' own: table-indent 6.9% to 0.09. And bug65649's last page per
section was two things in one merged header cell: Word draws a cell
merged down several rows from its first cell's top and its LAST
continuation cell's bottom, where we wrote the first cell's sides on
every row; and a cell ruled at 1.5pt over 0.75pt rows loses that width
from its text area, so Word wrapped "зарплаты" onto a second line and
we did not — a line less per header, a page more per section. 12.8% to
4.7%, 180 pages against 177. The method, for the record: swap the
original's table in (7.2%), then its header rows, then one row, then
one cell's sides, printing each; the enlarged crop of the two headers
side by side showed the wrap. issue_51265_3's last 4% was one missing
thing in the styles part: a named style's TAB STOPS were never written,
and its header style centres and right-aligns the header's pictures by
two of them (0.00% with them). At that point: 111 scored, 102 within
1%, 8 within 5%, none within 15%, form_footnotes on its knife edge.

(What was open at that point — bug65649's equipment table, form_footnotes'
page break, delins — is brought up to date under "Standing" below.)

Whether Word's prints of the originals can be kept across sessions was
tried and answered no. Word prints some originals differently from one
session to the next (font substitution falling another way: heading123
4.7%, delins 4.6%, bug59058 7.9%, drawing 19.7%), and WHICH ones differ
changes per session — drawing was pixel-identical across two sessions
and 19.7% off in the third — so a cache behind one stable canary
reported two regressions that were only the cache. Reuse is
session-bound again; `DOCX_RENDER_REUSE=1` is there for quick iteration
and its numbers are not to be committed. The same effect moves SCORES:
drawing is 0.56% in one session and 6.4% in another with the same copy,
so a jump on a file with substituted fonts is checked by reprinting the
previous build's copy in the same session before it is believed.

Then form_footnotes' page break, the last large number. Its last row
carries `w:tblPrEx` — a row's own exceptions to the table's borders —
and its cells rule single sides at their own style (a double bottom
under single inside rules); both were dropped, and the row was 2pt
short of breaking where Word breaks it. A row's border exceptions are
kept as written (not its cell-margin ones: margins are flattened into
the table's, and drawing's exception restating them put margins back),
and each cell's `w:tcBorders` is kept verbatim and written back while
the table's border switch is what the file had. 44% to 37%. The rest
was three small things found by measuring anchors to a hundredth of a
point down the page until one moved: a spacer paragraph that says
`w:before="0"` under a style with space before (zero is now written
there); `w:sym` runs — a character that means its glyph only in the
named font, Symbol F094 being a box — written back as text in the
body font; and bullet levels whose `w:lvlText` is such a private-use
code, read as a round bullet and written back as one. With those, every
anchor on page one sits where Word's original has it and the last row
breaks where Word breaks it: form_footnotes 0.64%, checkboxes 1.2 to
0.01, Numbering 0.3 to 0.06.

**Standing at the end of the fourth round (2026-10-11, commit
ab4bc7c4).** 111 scored, both sides printed in one Word session; 103
within 1%. Round three ended at 35 within 0%, 48 under 1%, 15 under
5%, 13 above. Gates: 304 unit tests, the corpus at 122 converted and
the 8 expected read failures, `ooxml-check` clean. Word refuses the
ORIGINALS of the fuzzer, truncated, unicode-path, crash, deep-table-cell
and ExternalEntity files, so those are outside the scored set. The
eight above 1%, and what is known of each:

- **drawing, 6.2%** — session-dependent: 0.56% in another session with
  the same copy. Check in a fresh session before touching it.
- **delins, 5.1%** — not ours: Word prints its ORIGINAL 4.6% differently
  from one session to the next (the tracked-change balloons).
- **bug65649, 4.1%** — 180 pages against 177. Its equipment table (page
  139) autofits to other column widths than the original's, and no
  single part explains it: the original's table markup inside our
  package prints like ours, and so do its styles, settings, numbering,
  theme and font table swapped in one at a time. Next: a cut-down copy
  of that one section.
- **rtl 3.4%, bug57031 3.0%, Bug54771b 2.0%, bug59058 1.3%, FancyFoot
  1.0%** — not yet investigated. rtl's Latin runs carry `w:rtl
  w:val="false"` and a language we drop; bug57031's worst pages are
  its SAS tables, a point a row.

How to work the next one: probe with a cut-down copy (a 180-page print
per question is what made this round slow); swap one part of the
original into our package and print (styles, settings, numbering, then
one table, one row, one cell); measure anchors to a hundredth of a
point down the page on both sides until one moves; and batch unrelated
fixes into one Word pass.

Two harness lessons from the round. Never swap a copy in while the
driver is opening it: four "Word refused" verdicts were the "experienced
an error" dialog from a file replaced mid-open, and Word then refused
other files until it was relaunched. And `test/ooxml-check.py` had let
two things through that Word calls unreadable content — a zip with two
entries of one name, and two drawings with one `wp:docPr` id (a kept
anchor's and a generated picture's) — both found by bisecting
drawing.docx with hand-made variants opened by script; the checker
fails on both now. Word facts settled the same way (a two-variant file,
printed and diffed): `beforeAutospacing` is 14pt and none between list
items; an empty `w:compat` means legacy layout — and is therefore
kept, since the original was laid out by it. (The same method
"settled" that an empty paragraph's height ignores its mark's size,
and that was wrong — see the fourth round.)

**Fifth round, 2026-10-11 (commits 0bad9f05, bd0608d1, 281e8ace).**
The eight above 1% taken one at a time, each by reading the two
packages side by side before printing anything; every one ended in
markup the writer dropped or restated. 111 scored in one Word session:
67 at 0.00%, 43 more within 1%, one above (delins 4.65%, which is
Word's own drift between prints of its original). The fourth round
ended at 103 within 1% and eight above.

- **rtl 3.41% → 0.00.** The file names a complex-script face (`w:cs`)
  apart from the Latin one, and we wrote the Latin face into every
  slot; Word then substituted another Arabic font and wrapped each
  paragraph elsewhere. `CharStyle` carries the `w:cs` and `w:eastAsia`
  faces now, and the document defaults keep their `w:kern`.
- **Bug54771b 2.04% → 0.00.** Two rules: a paragraph style with no
  `w:basedOn` starts from the document defaults, not from Normal (its
  No Spacing had come back with Normal's 10pt after), in the body and
  in table cells; and a floating table keeps its `w:tblpPr`.
- **FancyFoot 1.03% → 0.01, SimpleHeadThreeColFoot 0.83% → 0.01.** A
  one-line footer was flattened to plain text whatever it held. One
  with a border, a font, an alignment tab (`w:ptab`) or an empty
  second paragraph is kept whole now, as the multi-line ones were.
- **bug57031 3.03% → 0.31.** `w:tblCellSpacing` of ZERO is a
  statement: Word then rules each cell on its own and every row
  stands a border taller. Probed with five variants in one pass — the
  table-level zero alone does it; the rows' own and `w:hideMark` add
  nothing.
- **bug59058 1.27% → 0.85.** A style's `w:vanish` was not written, so
  the HTML importer's "Top of Form" markers printed.
- **bug65649 4.06% → 0.03, 177 pages on both sides.** Two finds. The
  default tab distance (`w:defaultTabStop`, 708 twips in a third of
  the corpus) was always written as 720, which moved every typed
  "4.2.8.<tab>text". And the three-page drift that no swapped part
  explained was one optional hyphen: `w:softHyphen` was written back
  as the character U+00AD inside `w:t`, which is no break opportunity
  to Word, so the equipment table's header word stayed whole and its
  autofit column grew. Both hyphens are elements again.
- **drawing 6.20% → 0.88.** Not session-dependent after all. A table
  most of whose cells state a `w:tcMar` was saved with the cells'
  margins as the table's, so the cells stating none lost the table's
  own 5.25pt. Cell, row-exception and table margins go back as read.

**The same day, the documents left under 1% (commits ae8e7db1,
138bd1fc, 2e8a2190 and the one after).** Each again a rule, most of
them about files no word processor wrote. 111 scored: 72 at 0.00%,
110 within 1%, nine above 0.1%.

- **drawing 0.88% → 0.04.** A paragraph's `w:divId` names a block of
  `word/webSettings.xml`, and Word spaces the paragraph by that
  block's margins (4.5pt under the last banner). The reference and the
  part are kept — the part only for a document that names a block.
- **form_footnotes 0.64% → 0.15.** A list's own `w:lvlOverride` with a
  whole `w:lvl` replaces the definition's level; its three
  instructions had come back starred and deeper.
- **MultipleBodyBug 0.55% → 0.00.** Every `w:body` is read.
- **Bug66263-paragraph 0.60% → 0.00.** A `w:t` without
  `xml:space="preserve"` loses the XML whitespace at its ends (a
  no-break space stays). And a package with NO styles part is laid out
  by Word's Normal of the day — 12pt, kerned, 8pt after, lines of
  278/240 — measured off the print's line boxes to a hundredth of a
  point (`pdflines`, below). That is the template's word, not the
  file's, so it is this Word's answer.
- **bug59058 0.84% → 0.22.** A link whose run names no Hyperlink style
  is not underlined (the save names the style, so the run says "none"
  over it, and the editor draws it plain); and an inline picture kept
  as written keeps its run's `w:rPr` — a character border and a size
  that set the line it stands on.
- **HeaderFooterUnicode 0.30% → 0.00, headerFooter 0.22% → 0.00.**
  The generated one-line footer is centred; the file's sat at the
  left. Every header and footer part is kept now and written back
  while the editor's text for it is still the file's, which retires
  the "is it rich" test altogether.
- **bug57031 0.31% → 0.01.** A table ruled by its cells takes the
  colour its own `w:tblBorders` names.

Left: delins 4.65 (Word's own drift between prints of its original),
55966 0.46 (Word hides the second of two content controls marked
`w:showingPlcHdr`; we show its text — a quirk of a hand-made file, not
copied), bug59058 0.22, Tika-792 0.21 and WordWithAttachments 0.18
(change balloons), then nothing above 0.15. Not modelled by our own
layout, only kept for Word: the `w:cs` face, the default tab
distance, a floating table's position, per-cell margins, HTML block
margins. Eight originals state `w:autoHyphenation`, which is dropped;
none of them shows it in the score. An edited header or footer leaves
its kept part in the package unreferenced (as before). Gates: 313
unit tests, the corpus at 122 converted and the 8 expected read
failures, `ooxml-check` clean. (`test/run.sh` fails one step on the
Mac, termd's remote sessions, a broken pipe in `termd/test-termd.py`
— not Office's.)

Two small tools did the measuring once pages differed by a pixel:
PDFKit scripts that print each line's box on both prints and only the
lines that differ, and the fonts with their sizes:
`test/pdf-lines.swift` and `test/pdf-fonts.swift`.

Method note: this round printed far less than the fourth. Diffing the
original's and the copy's XML for the first differing paragraph on
the first differing page found six of the seven causes before Word
was asked anything; Word was the check, and the probe only where two
candidates had to be told apart.

**Chinese government documents, 2026-10-11/12 (commits a1e9fcb6 to
6998ec5a).** A second corpus, because POI's is Western: 679 .docx
tagged government + Chinese on docxcorp.us (520 of type "policies";
113 of the first 179 simplified, the rest Taiwan's traditional), in
`~/.cache/starling/docx-zh-gov/{in,out}` with a `manifest.tsv`, never
in the repo. `test/docx-corpus.py --dir IN FILES…` round-trips them
(name the files: without them the script fetches POI into the
directory). Round trip: 679 of 679 after two fixes it found — a kept
list number's `w14` text effect in a numbering part that declared `w`
alone (10 files ill-formed), and a SmartArt's `dgm:relIds` (`r:dm`,
`r:lo`, `r:qs`, `r:cs`) not treated as relationships (3 files).

Then Word's prints of a seeded random tenth (68 documents,
`~/starling-word-check/zh`). The first pass was sobering: of the first
nine scored, eight were 15-46% off. Standing after two batches: 15
identical, 42 within 1%, 10 at 1-5%, 12 at 5-15%, 4 above — against
33 within 1% and 27 above 5% after the first batch. What a Chinese
document is set by, none of which the Western corpus exercised:

- **The line grid.** The last section's `w:docGrid` (kept sections had
  theirs) and the paragraph switches that go with it: `w:snapToGrid`,
  `w:kinsoku`, `w:wordWrap`, `w:overflowPunct`, `w:topLinePunct`,
  `w:autoSpaceDE/DN`, `w:adjustRightInd`, `w:textAlignment`, and the
  measures in character and line units that override the point ones
  (`w:firstLineChars`, `w:beforeLines`…). Resolved down the style
  chain into `RichParagraphStyle.eastAsian` and written on every
  paragraph.
- **Word's own paragraph defaults.** A styles part whose
  `w:docDefaults` has NO `w:pPrDefault` (WPS writes them so) is spaced
  by Word's Normal — 8pt after, lines of 278/240, measured off line
  boxes — where an EMPTY `w:pPrDefault` means none. Six of the 68,
  every one 6-37% off, to 0.0-3.2.
- **Sections.** A section's `w:type` is how THAT section starts, so the
  break after a section is the next one's to say (a "continuous" body
  after a cover section had been pushed to page two); the last section
  keeps its type, `w:pgNumType`, gutter; and a section break in the
  text keeps the header and footer parts it names, which the sections
  after it inherit (a letterhead line lost on all 18 pages).
- **Fonts.** `w:rFonts w:hint`, a separate `w:hAnsi`, and the Latin
  face read from `w:ascii` alone — a run naming only `w:hAnsi` beside
  `w:eastAsia` had its digits come back in the East Asian face. Per-run
  `w:lang`, `w:w`, `w:position`, `w:bdr`, `w:fitText` kept; the
  defaults' `w:lang`, `w:themeFontLang`, `w:characterSpacingControl`.
- **Tables.** Each cell's own `w:tcW` (percentages mixed with "auto"
  are neither all-auto nor the grid), `w:noWrap`, a merged cell's
  continuation paragraphs, a table centred by its rows' `w:jc`.
- **Lists and breaks.** Number formats by Word's name
  (`chineseCounting`, `taiwaneseCountingThousand`: "壹、" had come back
  "1、"), start and alignment; a page break that OPENS a paragraph is
  the paragraph starting a page, not an empty paragraph and a break (a
  blank page where the page was full); a paragraph border's line style
  (`thinThickSmallGap`, the red rule under a letterhead); a style's
  letter spacing and kerning.

None of it is laid out by the editor; it is kept for Word. The POI set
is where it was (111 scored, 110 within 1%) — after a scare: Word's
print dialog holds a paper for the session and changed it under the
regression pass (A4 as 595x842, then 595.28x841.89), so kept prints of
the originals sat half a point off the fresh copies and forty
documents "regressed" by up to 10%. `pdf-diff` reports `paper=differs`
now and the gate prints that original again.

**The sample again, 2026-10-12 (commits after 51f49e83, to the "List
Paragraph" one).** Two more batches, worked the same way — a census of
what the copy lacks (now by attribute as well as element), then the
first differing line. 68 scored: 22 identical, 58 within 1%, 4 at
1-5%, 6 at 5-15%, none above. (42 within 1% and 16 above 5% a day
earlier.) The POI set was printed whole again afterwards: 111 scored,
77 identical, 110 within 1% — it gained five identical documents from
rules found in Chinese ones. What the batches were:

- **Numbered styles.** A style's list and its level are inherited
  apart ("heading 3" states the level, the list comes from "heading
  1" under it: every 一、 and (一) had gone); a style naming a list and
  no level is the level the numbering ties to it (`w:lvl`'s
  `w:pStyle`); and a numbered style's own indent stands over its
  level's.
- **Header and footer styles.** The styles of every header and footer
  part the document relates to are written, and a style now carries
  its border, shading, East Asian switches, an explicit "left" where
  Normal is justified, letter spacing and kerning — a kept part's
  paragraphs have only their style to tell them (page numbers came
  back at the body's size, a line low).
- **Rows and columns.** `w:trHeight w:hRule="exact"` stays exact (12
  pages to the original's 9 without it); a fixed layout stated by the
  table's style; the last section's `w:cols` as written.
- **Tabs.** Stops ADD to the inherited ones, "clear" removes one and
  is written back, leaders and the num/bar kinds are kept.
- **Breaks and lines.** A page break that opens a paragraph is written
  back as the `w:br` it was (Word places the text after one by other
  rules than after `w:pageBreakBefore`); `w:line="0"` with "atLeast"
  is a statement; "distribute" by name.
- **Settings and fonts.** `w:noPunctuationKerning`, hyphenation, the
  line-break character lists, the embedded-font switches; and
  `word/fontTable.xml` with the fonts it embeds — a county notice set
  in embedded faces went from 30% to 1.2.
- **One of ours.** The writer added its own "List Paragraph" beside a
  file's style of that name under another id, and Word took ours.

Left: 33aa9899 10% (13 pages against 12), 64044a1d 10% (103 against
107), 457a8d62 9% (53 against 54; a line on page 9 breaks at another
character), 454e2e29 6.4% and 6cd1befe 5.1% (one justified line a
character out, then drift), 1a3c7aa0 5.5% (a footer 8pt low from page
2), 06c46ba9 4%, 90e0cea8 3% (frames in styles), a0e932c2 2% (a table
on page 2), e37f8d40 1.2%. Most of what is left is Word breaking a
line one character away from where it breaks ours — the same markup
on both sides as far as the censuses can tell — which is the place to
look next: run boundaries (`w:lang` per run survives, but runs of one
look are merged, and Word may measure across a boundary differently),
and `w:rPr` on the paragraph mark.

**The ten left over, 2026-10-12 (the commit after the plan update
282ff399).** The guess above was wrong: none of the ten was a run
boundary. Each had a cause the census had already listed and that had
been read as harmless, and `test/pdf-text.swift` (every line of both
prints as page, y, x, text — `diff` then names the first line that
moved) found each in a minute. 68 scored: 39 identical, 66 within 1%, two above (2.6 and 1.2), none above 5%. The POI set printed whole afterwards: 111 scored, 81 identical, 110 within 1%, nothing moved by more than 0.05. What they were:

- **Headings that keep.** The writer gave every heading style
  `w:keepNext`; a file's headings say for themselves. An impeachment
  text numbers every paragraph as "heading 5", and kept with the next
  each carried its last line over the page (8.9% to 0.01).
- **Page references.** Word brings `PAGEREF` fields up to date when it
  prints, so a contents page flattened to text kept the numbers the
  file was saved with while the original's moved (two documents, 4 and
  10%). The field's result text carries its instruction
  (`CharStyle.field`) and goes back as the field; a paragraph carries
  the names of the bookmarks that start in it. Only `PAGEREF`: a `REF`
  shows its bookmark's CONTENT, and a bookmark is written back at its
  paragraph's start with no extent.
- **Break characters.** A column break that opens a paragraph is a new
  page on a page of one column (read as a line break, an outline began
  a page early). A paragraph that is only a page break, or ends with
  one, gets the break back as that character at its end
  (`breakEndsPrevious` on the paragraph after): Word drops the space
  before a paragraph that follows a break character and keeps it under
  `w:pageBreakBefore`, 6pt on every chapter page of a handbook — and
  with the section's last paragraph it is a blank page of its own. The
  break keeps its run's properties: an indent counted in characters is
  measured by the paragraph's FIRST run, which the break is.
- **Kerning decides punctuation.** Word closes up 》《 only where the
  text kerns. A style that is not Normal's child has no kerning unless
  it says so, and we write Normal's kerning as the document default:
  such a style now says `w:kern` 0 (a plan's body lines each held a
  character more than the original's).
- **Frames.** A paragraph's `w:framePr` is merged over its style's,
  attribute by attribute (a standard's cover title states its height
  and x; the style states the anchors, the width and the y).
- **Character styles.** All of the file's are written back as they
  were: kept markup names them (a footnote's own mark was full size
  without "footnote reference", and each note broke a character
  early). Where the file has a "Hyperlink" or a note reference style
  of its own, our runs name it and ours is not added beside it — the
  "List Paragraph" bug again, and "footnote text" had it too.
- **In a table cell** Word ignores a break character and honours
  `w:pageBreakBefore` by moving the row: a cell's leading break goes
  back as the character too.
- **A border that is no line still has its space.** Word stands text
  off a `w:val="none"` edge by the edge's `w:space` (found by
  printing a hand-patched copy: 1.19% to 0.11). Kept as a line of no
  width that the painter does not draw.
- **Smaller.** `w:eastAsianLayout` (two lines in one) is kept on a
  run; `w:evenAndOddHeaders` is written when an even-page part belongs
  to an earlier section only.

Left: 90e0cea8 2.6% (a standard: its cover is right now, a table on
page 8 sits 1-2pt off) and 06c46ba9 1.2% (a handbook: a caption 5pt to
the side on page 47, then small drift). Everything else is under
0.7%. Bookmarks are written at their paragraph's start with no
extent, and only `PAGEREF` among the fields is kept.

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

### The corpus in the repository, 2026-10-12

The documents and Word's prints of them are now checked in as
`test/corpus/docx`, laid out like the .pptx and .xlsx corpora: the 130
POI documents and the 68 Chinese ones of the sample (`zh-*`), Word's PDF
of 179 of them, and two score files. `roundtrip.tsv` is the gate this
plan has been about (176 of 179 within 1%). `baseline.tsv` is new: the
first sweep of this app's own drawing against Word's print
(`test/docx-app-render.sh`), which nothing had measured before — mean
12.6% over the 179, POI 4.7% (median 0.9%), the Chinese sample 25.6%
with no document under 2%, because lines and pages break elsewhere
(1,275 pages against Word's 1,239). That is the painter's work list, and
a different one from the writer's.

### The painter against Word, 2026-10-12

The work list of the section above, worked. `test/docx-app-render.sh`
scores pixels; `test/docx-line-match.py` reads both prints' text and
says what share of Word's lines this app sets on the same page at the
same height, and where a document first parts from Word. The second is
the one to steer by: a paragraph that breaks one character early moves
every line after it, and the pixel mean hardly notices which paragraph.
The method that found every rule below is the same each time — take
the first line that differs, read that paragraph's XML and the
settings, write a ten-line lab document that isolates the suspected
rule, print it with Word, and read the widths off the PDF.

Standing, sweep 6: POI 3.8% mean (median 0.8%), the Chinese
sample 17.4% (median 15.4%) against 25.6% at the start; lines where
Word has them 62% of POI's and 45% of the Chinese sample's (42% and
5% at the start), 40 of the 68 with Word's page count.

What Word does, by what was measured (each is in the code beside the
line that does it):

- **An unhinted curly quote gives nothing, in Word for Windows (2026-10-29).**
  A “ ” ‘ ’ whose run is not hinted `eastAsia` is set in the Latin slot,
  full-width or not by the face there, and no line-end squeeze takes room
  from it. Labs e5q–e5t (zh-e5eb092a's package, mode 14, compressPunctuation,
  zh-CN, its quotes unhinted in Normal (Web)'s 宋体 hAnsi): "府”，" is taken
  only while "…府”" fits with every quote at its em; the same quotes as 《》
  let "》" give half its em, and "《" nothing. The Word-for-Windows prints
  that squeeze full-width quotes have them hinted East Asian. Pair
  tip0 (8d52c101) → q1, 756 documents, Windows mode: zh-e5eb092a 96.9 → 100,
  zh-4a2ab598 99.6 → 99.9, nothing else moved; the same two again on
  d645363c.

- **Overflowing first-line indents in fixed text boxes (2026-10-28).**
  In measured standalone DrawingML `noAutofit` frames, Word keeps the first
  glyph on line one at its stated positive indent even when it cannot fit.
  Following text wraps; the overflowing first line clips at the frame along
  its reading direction. A layout placeholder must not take a line by itself
  or clamp that glyph back inside. Measure the glyph with the resolved Word
  face, reserve its first-line room, then restore the indent while painting.
  Horizontal frames and zero-inset turned frames are covered; upright text,
  autofit, groups and separate ruby/scale/tab painters remain outside this path.
  Paint complementary first/rest text masks: horizontal clipping bands corrupt
  a later line's overlapping ink under tight exact spacing. The 11-page
  shared-font regression checks indent/rotation plus white-first overlap pairs
  against explicit breaks; fresh Word, native in both modes and browser pass.
  General frame clipping remains unresolved: broader candidates dropped
  headers, dynamic page numbers and other labels and were rejected. Full
  `drawing-wordart-final`→`box-first-line-masks` pair: Windows zh-b24b396a
  330→339/362, Mac 328→337/360; 756 documents per mode, no missing documents,
  no drops, no page-count changes, and all other normalized geometry identical.
  Engine remains `3841e45e…`; no cancelling-errors exception is needed.

- **DrawingML WordArt (2026-10-27).** A shape's `fromWordArt` text follows
  its rotation and warp, rather than also appearing as an ordinary text-box
  overlay. Keep its resolved paragraph/run styles and its original XML for
  saving. `textSlantDown`'s adjustment sets the band's thickness (28569–100000),
  not its displacement: 100000 is rectangular. Isolated Word controls and
  ECMA's preset geometry agree. Fit visible glyph outlines into the text
  rectangle: advance bearings and line leading are not ink. Native and skwasm
  now expose the same read-only ink query; tight outline bounds avoid raster
  padding changing the fitted shape between screen and PDF sizes. Bitmap-only
  glyphs retain a raster-bounds fallback. Fifteen cross-engine probes agree,
  and the permanent font-scale gate rejects the earlier raster-bounds attempt.
  Word's no-autofit controls match with default and zero margins. Autofit sizing
  and font appearance remain measured residuals, not claimed exact. The full
  `ink-base`→`drawing-wordart-final` pair improves Windows zh-b24b396a 328→330/362,
  with no drops in either mode; only this document's drawing text changes.
  Requires engine `bd7be6b10e5`; older web hosts use the existing advance-box
  fit when the optional ink query is unavailable. The final browser/native
  layout gate and shared-font WordArt pixels agree. No live deployment.

- **Odd/even section starts (2026-10-27).** Explicit `oddPage`/`evenPage`
  starts use the continued logical page number, including an inserted blank
  with no header/footer. A stated numbering restart is rounded upward to the
  requested parity without itself adding a blank; the separate alignment rule
  for restarted numbering with even/odd headers still applies. Eighteen fresh
  Word controls cover prior page counts/numbers, restarts, header modes and
  floating tables. Process the section break once before positioning a
  page-anchored table: its vertical offset must not trigger a second break.
  zh-291fcea7's Mac form now follows the blank eighth page, matching Word's
  12 pages; 182→232/296 lines, both-mode full pairs with no other changes.

- **Screen and native parity (2026-10-27).** FreeType's 26.6 requested size
  must not quantize linear advances: 11pt at screen scale is 14⅔px, whereas
  PDF scale uses 220px. `skia-freetype-linear-size.patch` restores the requested
  scale for linear advances without changing hinted outlines; the browser's
  word-boringcrypto wrapping then matches Mac CoreText. `test/office-layout.sh`
  also checks fractional-size scaling directly. Its line dump reports the
  advance pagination consumes, not raw fallback ascent + descent: an exact
  13.2667px strut stays that height even if a missing U+2010 glyph uses a
  taller fallback face. Compare identical document bytes, including welcome's
  platform-specific shortcut labels, before diagnosing a layout difference.

- **Lines.** An East Asian face's line is 1.3 times its ascent and
  descent; on a line grid a line is whole pitches; an exact height
  ignores the grid; the baseline sits 13/16 down an exact line and is
  centred in a grid's. A section has its own grid, and one without
  `w:docGrid` has none — the last section's is not the document's.
- **Characters.** Word on a Mac has few Chinese faces and sets the
  rest in Microsoft YaHei (`OFFICE_WORD_FONTS=mac`). A name the font
  table declares in the Latin character set that Word does not have
  ("S宋体") is a Latin face. Curly quotes in East Asian text are
  full-width marks, an em each with the blank outside (the opening
  one's blank rides a word joiner before it). A character
  scale (`w:w`) is a true narrowing — drawn from a second painter at
  full size under a narrower canvas — and takes the face's OS/2 line
  metrics, which for 华文中宋 are not its hhea ones.
- **A stand-in's widths.** The Latin of 微软雅黑, 微軟正黑體 and
  等线 is drawn by a shipped sans, and was as wide as a scale for
  each kind of character made it: right on average and up to six per
  cent off for one letter ("C" 11.4pt for YaHei's 10.7 at 16pt), a
  character of a line in a paragraph with a few words of Latin. Each
  of U+0020 to U+007E is now set exactly as wide as the face's own
  table has it, regular and bold, with the stand-in's kerning off
  (Arial closes up a pair of ones). The letters of a Chinese face
  Word on a Mac does not have are YaHei's too, like its ideographs.
- **`w:balanceSingleByteDoubleByteWidth`** (two thirds of the sample):
  a space is half an em unless it stands between two Latin
  characters; character spacing counts twice on a full-width
  character; the automatic space beside an ideograph is a quarter of
  half an em and the East Asian face's average width; two half-width
  characters share a character grid's addition.
- **Line ends.** A closing mark hangs past the margin and a line's
  marks give up to half an em each (`w:characterSpacingControl`) — in
  a justified paragraph only from compatibility mode 15 on, and in
  every paragraph below it, which is three quarters of the sample.
  Under `w:useAltKinsokuLineBreakRules` a mark hangs by half an em,
  and not at all where nothing is compressed. Full-width quotes give
  like brackets; Latin ones do not, and hang by their own width. From
  mode 15 on the test for taking one more character is that each mark
  gives no more than the line would otherwise stretch by. A Latin
  word with no space in it moves whole, unless it is longer than a
  line or the paragraph says `w:wordWrap` off.
- **The automatic space** between an ideograph and a letter or digit
  is between two characters of a line: after a line's last character
  there is none, in any paragraph and any mode. Where punctuation is
  compressed and the mode is under 15, each such space on a line
  gives up to half of itself to take one more character, as a mark
  gives half an em, and under the same most of half an em a line
  (lab: 25 ideographs and "C" fit in 412.75pt, 2pt under their
  width; one "C" among twenty ideographs takes the next 4pt over,
  two take it 8). With `doNotCompress` none gives.
- **Pages.** Each section has its page setup, its header and footer —
  what it does not name it has from the section before, type by type —
  and its first page's own where it says `w:titlePg`. A header or
  footer taller than its margin pushes the text. A frame stands off
  its anchor by its `w:y`. Paragraphs keep with the next, keep their
  lines, and leave no widow or orphan.

Three things of the engine's own turned up on the way and are worked
around in `RichLayout`: its justifying sets every space of a line to
the one step it puts between ideographs, so the spaces after "第一条"
vanished (inside a justified line they are no-break spaces now, with
a zero-width space after them, laid out a second time and kept only
if no line break moved); its line heights do not add up to the
paragraph's under a forced strut when the first line opens with the
indent's placeholder (pages were cut a point into a line), and a
character count of lines at no width is not the count of break
opportunities where a space is set wider than its glyph (the line
fitter dropped the paragraph's tail).

- **In a table's cell nothing hangs.** A line of 24 ideographs and
  a full stop is taken at 25 ems in a cell and at 24 outside one, in
  every mode and alignment, and whatever `w:doNotWrapTextWithPunct`
  and `w:doNotUseEastAsianBreakRules` say (15 of the sample carry
  both; neither changed a line of the lab's). The marks inside a
  line give in a cell as anywhere; the one at the end gives its own
  half only from mode 15 on. Twelve documents of the sample came
  closer; the one that fell furthest (a5e2c3fa) now breaks its cells'
  lines as Word does and parts from it where Word splits a row over
  two pages and this app moves the row.

- **A row's rules are part of its height**, and which rules a row
  has is the cells' word before the table's. The line above a row is
  as wide as the widest of its cells' top sides and the bottom sides
  of the cells above them (a form whose cells rule their bottoms and
  say `nil` above: rows 31pt apart for 30 high); a table ruled round
  its rim whose cells each rule four sides has one above every row
  (the fifteen plan tables of the sample were 0.75pt a row short,
  twelve points by the foot of a page); a double line is three of
  its width; a height the file gives a row (`w:trHeight`) is the
  room between its rules, unless it is exact, which is the row.
  Sample: 22 documents closer, 2 further; mean 46.1% -> 49.9%.

- **A row parts over a page's foot.** A row was one block, moved
  whole to the next page — and the plan tables of the sample are
  rows a page tall. Word parts a row where every cell with something
  left can leave some of it above the foot: each cell is cut under
  its own last line that fits, and each goes on from the top of the
  next page. Before mode 15 no widow or orphan is kept in a cell (a
  row with room for one line leaves one); from mode 15 on a
  paragraph with widow control parts only with two lines on each
  side, so a cell of two-line paragraphs parts between them and a
  row with room for one line goes over whole. A cell merged down
  (`w:vMerge`) is cut at the foot like the rest and goes on under
  the repeated header, which is every row the file marks, not the
  first. Not parted: a row with `w:cantSplit`, a header row, a
  turned cell. Sample: mean 49.9% -> 59.7%, 18 documents at 95% or
  more (6 before), 46 with Word's page count (38).
  Not drawn yet: the line Word closes the parted row with at the
  foot of the page.

- **Text under a floating box.** Word wraps text into whatever is
  left beside an object with square wrapping — one character a line
  in a 30pt gap — but the paragraph's first-line indent comes off
  each side's room, and a first line that fits on neither starts
  under the object with the rest after it. That much is built
  (zh-8e8d4c40's page title in a box across the column, anchored in
  the paragraph of the line below); lines set beside a narrower
  object are not, and its text still runs over it (zh-37b6536f's
  charts).
- **A line spacing of nothing** (`w:line="0"` as a multiple): the
  paragraph takes no line and shows no text, where an exact 0 is
  ignored and an at-least 0 is the natural height. A footer whose
  last paragraph is written so sat a line too high here, and the body
  ended a line early on every page. zh-8e8d4c40 27.5% -> 87.6% with
  the two.

- **A table as wide as it says.** A table wider than its column was
  scaled down to it. Word keeps the width the table states
  (`w:tblW` in twips or per cent — 107% is 107%), out past the
  margin, and its indent sets it left: forms 482pt wide in a 439pt
  column lost a character a line in every cell. Sample: mean 60.6%
  -> 64.6%, median 76.3%; zh-a7728bc9 11 -> 98, zh-06f6a036 19 ->
  97, zh-3a2eba04 31 -> 96. Two fell (zh-0aac9d1a, zh-abe7e063):
  autofit tables Word re-fits by what is in the cells — a first
  column two characters wide where the file says 67pt — which
  neither width is; that fitting is the next thing tables need.

- **Tabs and the line fitting.** A paragraph with a tab in it was
  not fitted at all; it is now, its tabs as wide as they came out —
  a contents line typed with its own dots takes its page number by
  what its two commas give (zh-9e08ed28, zh-84702a67 56 -> 65). And
  a tab at a paragraph's end whose next stop is past the text's
  right edge takes a line of its own (zh-ae3d78ee's minutes, a tab
  after every full stop): without that the fitting, which now put
  the sentence on one line as Word does, left the paragraph a line
  short.

- **A letterhead.** Three things in one header (zh-e37f8d40,
  zh-1563bd74, zh-9dd9ce6d — the last now 100%): `w:textAlignment`
  "center" sets a line's text half way up the picture beside it,
  not on its foot; a kept shape that is a straight line or a plain
  box is drawn (`ImageAttachment.outline`: the rule under the
  letterhead, a text box's frame) where every shape was left out;
  and **no picture was ever drawn in a converted PDF** — they are
  decoded off to the side and the export did not wait. It paints
  the pages once to nowhere (a header's own layout asks for its
  pictures when first painted), turns the main queue until
  `RichLayout.hasPendingImages` is false, then paints. The pixel
  baseline was taken with every picture a grey box.
- **A table whose every row is marked a header** repeats none
  (zh-e37f8d40: 23 pages -> 17 for Word's 14).

- **Two readings of one page, merged (2026-10-13).** This work and
  another session's on the same branch each taught the layout Word's
  spacing between paragraphs and the room a table's rules take. What
  stands: the space after a paragraph and the space before the next
  share the room in every document that does not say
  `w:doNotUseHTMLParagraphAutoSpacing` — the other session's, and
  wider than the automatic-spacing case this one had measured (POI's
  lines where Word has them 62% -> 67%, median 76 -> 96) — with one
  `_spacing` both use (spacing in lines, the web's 14pt, contextual
  spacing; in a cell, where nothing is shared, the automatic kind
  still closes up). A row's rules are the cells' own under Word's
  rules (above), the table's plain ones elsewhere
  (`tableRulesTakeRoom`). zh-33aa9899 fell (68% -> 32%): a title, an
  empty paragraph and a heading, all with automatic spacing, stand
  20pt further apart than in Word.

- **Spaces set no line's height.** A line is as tall as its tallest
  character that is not a space, and a line of nothing but spaces as
  tall as the paragraph mark: three 20pt spaces under an 18pt mark
  are a line of 30.9pt, under a 14pt mark 23.9, and 18pt spaces under
  a 20pt mark 34.2. A run of spaces alone is laid out at the line's
  height here now. And the space two paragraphs share is the upper
  one's to give up: where contextual spacing drops its space after,
  what of the next one's space before lay over it goes too.
  zh-33aa9899 32% -> 82%, zh-ae655121 84% -> 94%.

- **A row with nothing of its own.** A row whose every cell is
  merged down from above has no paragraph, and the layout counted
  rows by their paragraphs: a cell merged over rows 2 to 4 was
  measured against rows 2, 4 and 5, never stretched its own, and its
  text ran into the block below (zh-15728c84). Such a row is placed
  now, as tall as the file says. Still open in that table: Word
  makes the two rows a two-line label is merged over 45pt where
  their stated heights add up to 31 — some of a merged cell's text
  is charged to a row in a way not yet measured.

- **A row in which no cell stands alone** (2026-10-13; that table's
  45pt). A row with a cell of its own is as tall as that cell, and
  the cells merged through it give nothing: a merged cell's text
  counts in the row it ends in, less what the rows above took. A row
  where every cell is merged on into the next row, or down from the
  one above, is sized by the cells themselves instead: one that
  starts there gives its first line and the space after its first
  paragraph (not its space before, nor its second line), one that
  continues gives the empty paragraphs the file wrote in it — their
  line height and spacing, 30pt lines make a 38pt row. Two rows
  merged whole with a 14pt line and Word's 8pt after are 22 and 22;
  a 2pt cell beside them and they are 2 and 20. The continued cells'
  paragraphs are read now (`CellRef.continuationParagraphs`); the
  rows with no paragraph are drawn and paged as part of the row above
  (`_CellGeo.ghostRows`), whose bottom line had not been drawn where
  such a row ended the table; and cells are stretched in the order of
  the rows they END in (a cell over three rows was measured before
  the one beside it had stretched the second). Labs `vm-a/b/c`,
  bodies 16-18 in `~/starling-word-check/lab/tools`; `rules.swift`
  there reads the heights of a page's horizontal rules.

- **The mark at a line's end in a cell, again.** "Nothing hangs in a
  cell" stands. But the line's last mark keeping its whole em there
  before mode 15 was Taiwan's Chinese: where Normal (or the document
  defaults) names `zh-CN` for East Asian text the last mark gives its
  half in a cell in mode 14 too, left or justified — twenty
  ideographs and a comma at 20.5 ems, with a comma among them at 21;
  under `zh-TW`, 21 and 21.5. Kerning, the cell's margins, the face
  and ten compatibility switches moved nothing (labs `cg`, `ck`,
  `cf±flag`, `cy-*`). 31 of the sample name `zh-CN`.

- **The rule under a row wants its room.** A row fits a page with
  the line below it — the next row's — and a row parted at the foot
  is closed with one: a line with 0.45pt under it goes over where
  the rules are half a point, with 1.05 where they are a point and a
  half, and stays with 0.1 where there are none (labs `ft`, `fu`,
  body 23).

- **Rows are laid out with what their page holds.** The rest of a
  parted row is a row again at the head of the next page: opened
  with a line, and no shorter than the height the file states
  (zh-15728c84: the second half of a row of 28.5pt at least is 29.4
  from the page's head with its line). And a row the flow made
  taller for a cell merged down into it is, on a page that took that
  cell up again at its head, only as tall as what is left of the cell
  asks — the room lost at the foot of the page before is not owed
  again (`_CellGeo.stretched`; the row's pieces are then its text
  from the top and its rules' last stretch). Both lines of a parted
  row are drawn now (`_paintPartedRules`), the closing one at the
  page's foot — Word draws it some points higher, under the last
  line that fitted and a space not yet understood (94.9 where the
  foot is at 90.2) — and a row that merely starts a page under a
  cell merged from the page before still has no line over it.
  Sample 68.8% -> 69.6% (median 88.7); zh-15728c84 5% -> 44%,
  zh-91e44bcb 76 -> 94. POI 66.6, bug65649 7.7 -> 4.5 (179 pages
  to Word's 178, from 176).

- **A row is not begun where its stated height has no room.** With
  36.5pt left on the page a row of 49.65 "at least" goes over whole,
  though a line of each cell would fit; one of 25 at least parts, as
  one with no height does — whatever its cells' vertical alignment
  (lab `np`, body 24). A cell merged down into such a row keeps on
  the page before only the lines over the last row placed there, and
  takes the rest with the row; the row on its new page is then as
  tall as what it was handed asks, which can be MORE than the flow
  gave it (one line left behind, four taken over: 76pt for the
  flow's 61). A row shown taller than the flow has it draws its
  rules in stretches (`PagePiece.inner`). And a row that starts a
  page under cells merged from the page before has a line over it.
  Sample 69.6% -> 70.8%, 53 documents with Word's page count;
  zh-15728c84 44% -> 81% and its ten pages, zh-e6d54ae4 18 -> 54.
  Two a point down (zh-abe7e063 33.8 -> 32.8, zh-e6d54ae4 by 0.3)
  from the merged cell's cut, not looked into.

  The three together: Chinese sample 67.0% -> 68.8% of Word's lines
  (median 82.2 -> 86.7), 51 documents with Word's page count; ten
  documents closer, none further. POI 66.7 -> 66.6 (bug65649 8.6 ->
  7.7).

- **Cambria's clone was not one (2026-10-13).** zh-4b8e0abc sets
  Indonesian beside its Chinese in the theme's Cambria, justified,
  and every line of ours took a word more than Word's. The bundled
  Caladea was the build on github.com/huertatipografica/Caladea
  (1.001, 1000 units to the em — what Google Fonts serves): the name
  and the drawing, without the widths. "awal dari setiap tahapan
  yang ada." at 14pt is 204.9pt in Cambria and in Word's print, and
  197.0 in that Caladea; over a line of mixed text it runs 3 to 6
  percent short in all four styles. The 2013 ChromeOS release
  (`crosextrafonts-20130214`, 1.002, Apache 2.0) is the clone:
  523.73 against Cambria's 523.71 over an 84-character line, and
  within 0.3 in bold and italic. It is bundled now; Carlito was
  checked the same way and is exact. zh-4b8e0abc 20% -> 31%.
  A deck or a sheet set in Cambria moves with it.

- **Space before at a page's top (2026-10-13).** Labs `sb-a/b`
  (the paragraph pushed over by a spacer, `tools/body25.py`),
  `sc-a/b` (the other ways a page starts, `body26.py`), `sd-a/b`
  (break characters, `body27.py`), `se` (line and keep settings,
  `body28.py`), in two source packages (mode 14 and 15) and each
  with its mode swapped. A paragraph that heads a page because the
  page before filled up leaves its space before behind — 18pt of it
  gone, the line where a paragraph with none has it. So does one
  after a break character that ended the paragraph above, and an
  empty paragraph (its line stays). The space still counts toward
  whether the paragraph fits where it is: a line with room for
  itself and not for its space goes over, and stands there without
  it. Kept: the document's first paragraph's; a new section's; that
  of a paragraph which itself BEGINS with the break character
  (seven of the Taiwanese plans, which open 貳 that way, fell from
  98% to 20–88% until this was told apart); and under
  `w:pageBreakBefore` it is kept in mode 14 and left behind in mode
  15 — the one case where the two differ. `RichLayout`'s paging
  starts such a paragraph's first piece under its space.
  zh-4b8e0abc 31% -> 52%, zh-e37f8d40 62 -> 68, zh-e6d54ae4 54 ->
  56, zh-1563bd74 86 -> 88; POI's heading123 91 -> 100.

  Not found: zh-6d1afa56's headings begin with the break and Word
  sets them at three heights — the table under them starts 55.2,
  63.5 or 71.4pt below the page's top, as if none, half or all of
  the style's 17pt were kept. The heading alone in a lab (`se`)
  keeps all of it, whatever its line rule or keeps. What is before
  the break does not sort them (a blank page before: none, half,
  none; a table ending mid-page: half or all). Ours keeps all.

  The two together: Chinese sample 70.8% -> 71.4% (median 88.7 ->
  88.9), POI 66.6 -> 66.7.

- **Roman numerals in Times New Roman, and the squeeze in spaced
  text (2026-10-13).** Both from one line of zh-6cd1befe, which
  Word ends a character before ours. (1) A run that leaves "Ⅳ级" in
  its Latin face sets the numeral in Times New Roman, which has
  Ⅰ–Ⅻ and ⅰ–ⅻ of its own (Ⅰ a third of an em, Ⅳ 1.05); Arial,
  Calibri and Cambria have none and Word falls back to an em-wide
  East Asian glyph (lab `rn`, ten of each per fonts). Liberation
  Serif has none either, so the fallback drew them an em wide.
  `RichResolvedFace.otherAdvances` carries Times' widths by code
  point, regular and bold, and the line is set by them. (The run's
  Latin face is now looked up through Normal as its text style
  already was — a run naming no font had the theme's.) (2) The
  legacy rule that the next character is taken where it is "half
  an em or less" over, the line's marks giving it, is half of the
  character AS SET: lab `sq` (`body30.py`), two commas on the line,
  left-aligned, mode 14 — 16pt spaced -0.4 (an ideograph 15.2
  apart, the spacing counted twice where widths are balanced) takes
  one 7.55 over and not 7.65; spaced -1, 6.9 and not 7.1; unspaced,
  7.9 and not 8.1. zh-6cd1befe 32% -> 53%; Chinese sample 71.8%.
  The allowance over that half is now under a twentieth of a point
  (it was a twentieth): Word counts in twentieths, and the same
  document leaves a character that is 7.55 over a half of 7.5.

- **Circled numbers are Cambria Math's (2026-10-13).** The same
  document's lists open "⑤上级工作组…" and Word ended those lines
  one character before ours. Lab `si` (`body32.py`): the paragraph
  as written, and with one thing changed at a time — only replacing
  ⑤ with an ideograph let the character on. Lab `cn`
  (`body33.py`), ten of each per face: ⓪ and ①–⑳ are 1.2007 ems
  in a Times New Roman, Arial or Cambria run (1.22 in bold) —
  Cambria Math's glyphs, which Word falls back to — 1.328 in
  Calibri, which has its own (and so has Carlito), and an em in a
  run hinted East Asian (⑳ excepted: 宋体 has none). They go in
  `otherAdvances` for every Latin clone but Carlito.
  zh-6cd1befe 53% -> 86%; Chinese sample 72.3%, POI unchanged.

- **Mirrored margins, and the character grid again (2026-10-13).**
  All from zh-457a8d62 (`w:mirrorMargins`, a gutter of 227, a grid
  of `linesAndChars` with `w:charSpace="4127"`, mode 15), read glyph
  by glyph with the new `tools/glyphs` (PyMuPDF in the lab's venv;
  PDFKit's character bounds are not to be trusted).
  (1) **Mirrored margins**: the left margin and the gutter are the
  inside ones — an even page's text starts at the right margin's
  distance (70.9pt against an odd page's 82.25). Three documents of
  the sample have the setting; it moves no line and every pixel.
  (2) **A half-width character takes half of the grid's addition
  whatever follows it** (lab `cg3`, `body35.py`): on a grid of
  1.008pt a digit, a bracket and a letter are each 0.504 wider than
  the face sets them, before another of their kind and before an
  ideograph. Here it was the whole addition before an ideograph,
  which the automatic space had hidden: **that space is a quarter
  of the em and of the grid's addition** (4.25pt either side of a
  digit at 16pt), where it was a quarter of the em, and the two
  errors made the same sum. With `w:autoSpaceDE/DN` off — this
  document's Normal — every digit before an ideograph was half a
  point wide. All four lines of the lab now agree to 0.05 a glyph.
  (3) **A list's number is on the grid too**: "（2）" is 43.97pt
  wide, each full-width character with the whole addition and the
  digit with half, and the text begins after it.
  (4) **A mark gives half of itself as set**, as the character
  taken is measured as set: on the grid, two marks gave 8.5pt each
  to a line 16.9 over; spaced wider the threshold moves out with
  the spacing (lab `sq2`, `body36.py`: +0.3 takes 8.2 over and not
  8.4, +1 takes 8.8 and not 9.1) — the automatic space after a
  character is no part of it.
  (5) **A line that is over by a hundredth does not fit.** The
  hanging indent here is five grid cells and the 21st cell ends
  0.009pt past the margin: Word starts a new line. The fitting's
  hair (a hundredth of an em, from when the Latin widths were a
  stand-in's) and the layout's slack are now 0.005pt.
  `STARLING_RICHTEXT_FIT=<text>` prints the fitting of the
  paragraphs that contain the text.
  zh-457a8d62 19% -> 25% and its 53 pages; zh-7dc3afad 94.8 ->
  96.4, zh-91e44bcb 94.2 -> 95.7, zh-d68ac84a 75.4 -> 76.6. Two
  down, each one line that had been right for a wrong reason:
  zh-e27cd8bf (97.8 -> 97.0: with 法 now on the line above as Word
  has it, the next takes a 日 that is 7.99 over a half of 8.3 and
  Word leaves it — not understood, the lab says it is taken) and
  zh-a4b0f6ea (61.1 -> 60.8: Word closes "10.《" up by 3.9pt, a
  Latin full stop before an opening mark, and ours does not).
  Chinese sample 72.4%, 54 with Word's page count; POI unchanged.

- **The 2013 layout's squeeze, measured to a tenth (2026-10-13).**
  Labs `mm`, `mm2`, `mm3` (`body39.py`–`body41.py`, read by
  `read39.py`–`read41.py`): a justified line of full-width
  characters with k marks on it, the next ideograph over by d.
  Every kind of mark gives alike (，、。：；（）). With 26
  characters of 16pt on the line the next is taken up to: one mark
  8.0 (8.1 left); two 11.5 (11.6 left); three 12.6; four 13.3; five
  13.8; six 14.1; seven 14.3. With 16 on the line, two marks take
  12.9 and three 13.8; with 20, two take 12.3; with 10, two take
  14.0; at 14pt with 26, two take 10.0. One rule gives all thirteen:
  **the line is squeezed where that asks less of it than stretching
  would** — need / (half an em per mark) is no more than (what the
  line would stretch by without the character) / (a sixty-fourth of
  an em at each of its gaps) — and no mark gives more than its half.
  The test built on 2026-10-12 (need per mark no more than the
  stretch: 1/2, 2/3, 3/4 of an em) is that rule at 33 characters a
  line. It is right as it was for one case, lab `mh` (`body42.py`):
  where the character has a comma after it that hangs, one mark
  takes it 8.0 over, two 10.4 (10.8 left), three 11.6 (12.0 left).
  An ASCII bracket is no mark (lab `am`, `body38.py`), in an East
  Asian face or in Times.
  The rule is built for lines without spaces (those stretch at the
  spaces first: zh-33aa9899's line with a "3" in it is not squeezed
  for a character 8.4 over, Word widening the two automatic spaces
  from 3.5 to 6.3 instead — which the older test also gets wrong and
  this leaves as it was). Digits and brackets on the line count as
  characters. zh-457a8d62 25% -> 95%: its lines of 23 characters and
  two marks take a character 11.4 over. Chinese sample 73.4%
  (median 90.4), POI unchanged.

  A lab's "ours" must be converted with `OFFICE_WORD_FONTS=mac`, as
  the sweeps are: without it 標楷體 and 仿宋_GB2312 are the square
  faces their authors had, not the YaHei this Word falls back to.

  Seen and not built, lab `sh` (`body31.py`): where the character
  that is over is followed by a closing mark, Word's line ends 8.56pt
  past the margin whatever the overhang — the mark is set in its
  left half and the line's commas give the rest — where ours hangs
  the mark a whole em and has the commas give less. The lines break
  alike but for the last case (7.2 over, spaced -0.5, taken by Word).
  And with room enough in the commas Word draws the mark wholly
  inside the margin and hangs nothing.

- **Where a table stands, by its alignment and the layout's age
  (2026-10-14).** Labs `tc` (`body43.py` in zh-4c3793e8's package, no
  compatibility mode) and `tc15` (the same in zh-84702a67's, mode 15):
  ten tables, left, centred and right, with `w:tblInd` 108, 0 and
  600, with and without a stated `w:tblCellMar` of 200. Before 2013's
  layout a left-aligned table's edge stands its left cell margin —
  the table's own where stated, else its style's, else 5.4 — left of
  its indent, so that the first column's text lines up with the
  paragraphs'; a right-aligned one stands its right margin past the
  right margin; a centred one is centred as it is, and its indent
  counts for nothing. In mode 15 nothing is set out: the indent is
  the edge's place, left, centred or right. The code had set every
  table out by its style's margin and none by a stated one, which
  put zh-4c3793e8's centred timetable 5.4pt left of Word's (the
  "table x offset" of the open list). All twenty cases now agree to
  the point. `RichDocument.TableStyle.textOutdent` and
  `textOutdentRight`, `RichLayout._tableLeft`.
- **A space in an emboldened face is widened by half the spread
  (2026-10-14).** zh-232090e0's form has a line of 45 spaces then
  "申请时间:     年    月   日" in 楷体_GB2312 bold spaced -0.2, which
  Word keeps on one line and ours broke before the 日: 57 spaces at
  6.02 where Word's are 5.72. Lab `sp` (`body44.py`, twelve variants
  of the line): Word's KaiTi ideographs are 12.23 apart at 12pt
  unspaced — its fake bold's spread, which the stand-in models as
  0.21 of spacing — and 11.83 spaced -0.2, the spacing taken twice
  under `balanceSingleByteDoubleByteWidth` as known; its spaces are
  6.12 unspaced and 5.72 spaced, that is half the em, HALF the
  spread, and the spacing twice. Ours had added the stand-in's
  spread to the space twice over (once in the style the engine
  applies, once in the half-em correction that adds the style's
  spacing again). 4.3% -> 82.6% of that document's lines, nothing
  else moved. Not squeezed, this: with 46 spaces Word breaks, and
  left, right, centred and justified all alike.
- **In a cell, before 2013's layout, a Latin word at the line's end
  is taken whenever the marks and the automatic spaces can give what
  it needs (2026-10-14).** zh-4c3793e8's "服務專線：941025轉402
  田小姐", 41 spaces, "110.01.01" at 8pt, in a cell of 523.45: 8.8pt
  over, and Word sets it on one line with the full-width colon at its
  half (7.0, the glyph drawn 3.5 to the left so that its ink keeps
  its place) and each automatic space between a digit and an
  ideograph at 2.63 of its 3.5. Lab `ovc` (`body47.py`): the word is
  taken up to 10.5 over — the colon's half and the two spaces' halves
  exactly — and not at 11; an ideograph in its place up to 7.5 and
  not 8 (half its em, as in the body). The marks give first and the
  spaces what is still needed; the code had given all a share. The
  half-em test had been applied to the word too (4pt at 8pt), and
  stays for the body: zh-e27cd8bf's "20" and "2021" are taken there
  by Word within it, and the body lab `ov` (`body46.py`) was built
  on natural widths that turned out several points short, so it
  says nothing yet. zh-4c3793e8 47% -> 100%. Chinese sample 73.4% ->
  75.3% (median 91.1, 27 at 95%+), the two documents and nothing
  else; POI unchanged by the document (its mean reads 66.1 for a new
  empty "zero-length" fixture scoring 0/0).
  Not built from the same labs (`as`, `as-nc`, `as15`, `body45.py`):
  the automatic space is a quarter of the em in every setting tried
  — bold or not, 14 and 16pt, Arial or Times beside 標楷體, with and
  without `compressPunctuation`, before and in mode 15 — and a
  full-width colon, comma and full stop keep their em on a line that
  fits; the 10.5 and 2.6 of the document were the squeeze alone.
  (2026-10-17, Linux: a word in a cell that carries a full-width mark
  of its own — zh-06c46ba9's "1）", 9pt over — had no limit at all, and
  zh-d35cbbdb's cell took "1333、" 35pt over with six marks squeezed,
  where Word's print squeezes none and leaves it. Such a word is now
  taken up to half an em and what its own marks give: "1）" still,
  "1333、" not. zh-d35cbbdb 89.4 -> 89.7%; nothing else moved.)

- **Floating pictures that text wraps round (2026-10-14).**
  zh-37b6536f's report has five photographs anchored in empty
  paragraphs (`wrapTight`, `behindDoc`), and ours drew each as a strip
  one line tall, with the text running over where they should be.
  From Word's print, image box by image box (PyMuPDF), six rules:
  (1) a paragraph shown whole is not clipped to its lines when it
  carries a floating object; (2) a paragraph with less than an em
  beside the pictures over any of its first line, either side, goes
  below them — beside one photo 377pt wide eleven empty paragraphs
  stand in the 43pt left over; (3) a paragraph whose own picture would
  run past the page's foot goes to the next page with it; (4) a
  picture that would lie over one already on the page stands to its
  right; (5) two pictures in one paragraph that fill the column
  between them set its line under both; (6) where pictures leave no
  room for the lines of the picture-only paragraphs that anchor them,
  those lines go under them, one after another, while the pictures
  stay where their paragraphs first stood. A paragraph of nothing but
  floating objects is as tall as one of a single floating picture
  (in its mark's look), and a picture turned a quarter (`a:xfrm rot`)
  is laid out and drawn turned about its centre. Page 2 now matches
  Word's to half a point, pictures and text. zh-37b6536f 14.6% ->
  30.8% (its page 3 chart is not drawn), shapes-with-text 12.5 ->
  37.5, 60316 66.7 -> 81.8, zh-799c91cd 42.6 -> 43.0; nothing down.
  Chinese sample 75.6%. `RichLayout._paginate` (`bands`,
  `anchorRun`), `_wrapBoxes`, `_floatShift`/`_floatShiftY`,
  `_drawPicture`.

- **A fixed-layout table keeps its grid past the margin, and a grid
  line may hang below the page's foot (2026-10-14).** zh-454e2e29's
  form is 482pt of `w:tblLayout fixed` columns in a 468pt column; ours
  scaled them to fit, which wrapped "個案事實" in its header and moved
  every column 13pt left of Word's. Word keeps them (a table stating
  its width already did). And the empty paragraph under that table
  went to page 2 in ours, 35pt down, where Word keeps it on page 1 in
  32.7pt: lab `gf`/`gf2` (`body48.py`, `body49.py`) — a filler of
  exact height leaves R points, then one line of bold 標楷體 (YaHei,
  1.72 em here) on an 18pt line grid. The line fits where R reaches
  the foot of its natural height centred in its pitches, (h + n) / 2:
  16pt in 36 at 32 and not 31.75 (31.76), 20pt in 36 at 36 and not 35
  (35.2), 28pt in 54 at 52 and not 50 (51.1), 12pt in 36 never at 18;
  an empty line as one with text. Both labs agree case for case.
  `RichTheme.gridOverhang`, `RichLayout._overhang`. zh-454e2e29 24.7%
  -> 49.3%, zh-69bbcc3c 54.6 -> 68.7 (44 pages to Word's 45, was 43),
  zh-84702a67 +0.9, zh-e029cf49 +0.8; zh-25c4de17 38.7 -> 36.5 with its
  page count now Word's and page 1 whole (a line changes column on
  page 2). Chinese sample 76.1%, 55 with Word's page count; POI
  unchanged.

- **Where the cells rule the table, a side no cell states is not
  ruled (2026-10-14).** zh-a0e932c2's tables come from a PDF
  converter: text rows with no rules alternate with rows 1.6pt high
  whose cells rule their bottoms, and a last column of no borders at
  all; neither the table nor its style says anything. Most cells state
  borders, so the reader takes the table as ruled
  (`TableStyle.bordersFromCells`), and every side a cell left unstated
  then fell back to "ruled": a line above each thin row as well as
  under it, each row a point taller, and the empty last column boxed.
  Word draws only what the cells state. Page 1's fourteen rules now
  lie where Word's do, to 0.1pt. zh-a0e932c2 15.2% -> 22.7%; nothing
  else moved.

- **A picture's line in a table cell keeps to the line grid
  (2026-10-14).** zh-9c5d0c3f's road signs are 75pt pictures in cells
  on an 18pt line grid; Word sets each picture's line at 90pt, the
  extra above the picture, and the captions under them land within
  0.3pt of Word's now (rows had been 15pt short, pictures 10pt high).
  A picture paragraph is drawn from its line's ink top for that. Not
  outside tables: zh-90e0cea8's 25pt picture in the body stays in
  25.8pt at a page's foot in Word, where a snapped 31.2 went over —
  yet snapping body pictures too took zh-e5709b89 from 91.1% to 96.8%,
  so Word does snap some of them; not understood, left out. Also seen
  and left: zh-a0e932c2's second section is three unequal columns
  filled by column breaks with a one-column section after it on the
  same page, and the layout has one column count for the document
  (`pageSetup.columns`).

- **A left indent in characters counts from where the first line
  hangs (2026-10-14).** Where a paragraph states `w:hangingChars`, its
  `w:leftChars` is measured from the hanging line, and the left indent
  is the two together: `w:left` beside them is exactly that sum in 420
  of the sample's 422 such paragraphs (and plain `leftChars × unit` in
  every one without). zh-89385c94's cells say leftChars -45 with
  hangingChars 280 at 14pt, `left` 676: Word sets the text 33.8pt in,
  the first line 5.4pt out, where ours had both 39.2pt further left.
  zh-33aa9899 81.6% -> 98.6%, zh-9e08ed28 3.0 -> 19.0 (its page count
  now Word's), zh-89385c94 11.3 -> 16.3 (likewise), zh-e37f8d40 +0.6;
  zh-e6d54ae4 56.4 -> 52.1 with its line starts on pages 2-3 now
  Word's to the point (the loss is drift elsewhere in it). Chinese
  sample 76.8%, 57 with Word's page count; POI unchanged.

- **A lone page break's mark holds its page before 2013's layout
  (2026-10-14).** zh-9e08ed28 (mode 14) has, after its contents page,
  a paragraph of nothing but a page break, then an empty paragraph
  ending a section, then another. Word leaves page 4 blank but for the
  break's paragraph mark and starts the body on page 5; the reader
  folds the break into the zero-height section end, the page counted
  as empty, and the body began on page 4. The folded mark now holds the
  page. Not from mode 15 on, where the mark stays on the break's line:
  zh-ae655121 has the same three paragraphs and no blank page (applied
  there it added two). zh-9e08ed28 19.0% -> 53.0% (22 pages to Word's
  21 now, from later on); nothing else moved. Chinese sample 77.3%.

- **Page numbers restart per section (2026-10-14).** Each section's
  `w:pgNumType` (`w:start`, `w:fmt`) is read into its page setup; a
  page's number goes on from the page before unless its section
  starts on it and says where from, and its section's format writes
  it. Only the last section's had been read, applied to the whole
  document: zh-9e08ed28's body said page 8 where Word's says 1.
  zh-90e0cea8 +2.8, zh-9e08ed28 +3.1, zh-e5709b89 +3.1, zh-6d1afa56
  +3.6; nothing down. Chinese sample 77.5%.

- **`w:topLinePunct`: an opening mark at a paragraph's start gives up
  its blank half (2026-10-14).** zh-2b955411's Body Text style says
  `w:topLinePunct` (compress punctuation at a line's start) and its
  settings compress punctuation; Word sets "（六） 对市属企业…" 8pt left
  of its two-character indent at 16pt — the bracket's blank left half
  gone — and the line takes one character more than ours did (its
  "监"), which moved every line after. Done for the first line only
  (`RichLayout._topLineSqueeze`); a line inside a paragraph that starts
  with an opening mark is not, nor without the compression setting.
  zh-2b955411 62.1% -> 90.2%; nothing else moved. Chinese sample 77.9%.

- **A face the file embeds is set as itself (2026-10-14).** zh-e37f8d40
  carries six faces in its package (`word/fonts/*.odttf`, named by
  `w:embedRegular` in the font table), 仿宋_GB2312 among them, and this
  Word's print draws FangSong_GB2312 — not the YaHei it falls back to
  for that name elsewhere. Its ASCII brackets are half an em; YaHei's
  are a third, so a line of ours took a character more and the
  document ran 17 pages to Word's 14. Such a name now keeps the
  author's square face model under `OFFICE_WORD_FONTS=mac`
  (`OfficeFonts.noteEmbedded`). The faces themselves are not loaded
  (deobfuscating the .odttf and registering it would be the next
  step). zh-e37f8d40 68.3% -> 92.8%, 14 pages; nothing else moved.
  Chinese sample 78.2%, 57 with Word's page count.

- **A name declared Latin that Word has no face for is Calibri
  (2026-10-14).** zh-a4b0f6ea's runs name "S宋体" for ASCII, which its
  font table declares charset 00 (already read as Latin,
  `OfficeFonts.declaredLatin`). Word's print draws those digits in
  Calibri, 8.15pt at 16pt; ours fell to the Arial clone at 8.9, and
  "〔2021〕" then needed 33.6pt of squeeze where its marks have 32, so
  it went to the next line where Word keeps it. zh-a4b0f6ea 60.8% ->
  71.9%; nothing else moved. Chinese sample 78.4%.

- **A paragraph's space after stays at the page's foot (2026-10-14).**
  Where a paragraph's last line fits a page and its space after does
  not, pagination had cut under the line and carried the space to the
  next page's top, setting what followed that much low: zh-a4b0f6ea's
  page 8 heading 8pt below Word's. Word leaves the space behind.
  zh-a4b0f6ea 71.9% -> 78.4%, zh-c3dd22c4 94.5 -> 100, zh-6d1afa56
  +0.9 (a page nearer Word's count), and in the POI set Bug51170 16.2
  -> 32.5; nothing down. Chinese sample 78.6%.

- **"Outside" and "inside" follow the page (2026-10-14).** An object
  aligned `outside` stands at the page's outer edge — the right on an
  odd page, the left on an even one — and `inside` at the other; ours
  took them as right and left on every page. zh-a4b0f6ea's footers
  hold the page number in a text box aligned outside: page 10's now
  stands at the left, as in Word's print. Done for headers and footers
  (`RichLayout.leftHandPage`, set per page number); a body object
  aligned so is laid out once and keeps the odd side. Not done: that
  box is `wrap="none"` with `spAutoFit`, which Word shrinks to its text
  before aligning it — done the same day, below.

- **From 2013's layout on, a justified line's spaces give a quarter of
  themselves (2026-10-14).** Lab `js` (`body50.py`, in zh-4b8e0abc's
  mode-15 package): justified Cambria at 14pt, n spaces on the line, the
  next word over by d (widths from Word's own Cambria, `strw.swift`).
  Taken up to: n=1 0.5 (not 1.0), 2: 1.5 (not 2.0), 4: 3.0 (not 3.5),
  8: 6.0 (not 6.5), 12: 8.0 and on — a quarter of each space, 0.77pt
  of 3.09, with the line's last word's trailing space no part of it.
  Ours, all 85 cases alike now. This is the rule the automatic-space
  note below had not found for real spaces. The fitter now runs for a
  justified mode-15 paragraph with spaces even where it has no East
  Asian mark. zh-4b8e0abc (its Indonesian half) 52.3% -> 88.5%;
  nothing else moved. Chinese sample 79.1%.

- **A missing face's alternate name is used (2026-10-14).** The font
  table's `w:altName` names the face Word sets a name in when it has
  none of the name's own: zh-64044a1d's cover is 華康粗圓體, alternate
  新細明體, and Word's print draws PMingLiU, its 26pt empty lines two
  pitches each where the YaHei fallback made three. Only for a name
  Word has no face for, and only to an alternate it has:
  zh-232090e0's 楷体_GB2312 offers 方正楷体_GBK and Word draws KaiTi
  (applied there too, it lost 13 points). `OfficeFonts.noteAltNames`.
  zh-64044a1d 1.6% -> 20.9% (119 pages to Word's 103, was 121);
  nothing else moved. Chinese sample 79.4%.

- **On a line grid, a paragraph of mixed heights keeps every line to
  the grid (2026-10-14).** A paragraph whose runs snap to different
  numbers of pitches (12pt 標楷體, two pitches in the YaHei model, with
  Times digits and brackets, one) had no strut at all, and the engine
  stacked its lines 36 to 37.6pt apart where Word's are 36 each. The
  tallest run's strut, used so far for one-line paragraphs only, now
  holds every line of a gridded paragraph. zh-64044a1d 20.9% -> 27.1%,
  zh-15728c84 81.3 -> 89.4; nothing down. Chinese sample 79.6%.

- **A text box set to fit its text takes the text's width (2026-10-14).**
  `wrap="none"` with `a:spAutoFit` (VML: `mso-wrap-style:none` with
  `mso-fit-shape-to-text:t`): Word shrinks the box to its longest line
  and then places it. zh-1a3c7aa0's page numbers sit in a 144pt box
  centred on the margin, and stand at the page's middle in Word's print
  (x 291) where ours centred the whole box (226); zh-a4b0f6ea's, aligned
  outside, now stand 472/80 as Word's. `RichTextBox.fitsText`,
  measured per filled box (`_fitWidths`, keyed by its content: page 1's
  "-1-" is narrower than page 11's). Footers on zh-1a3c7aa0's odd pages
  still stand 8pt low. No line score moved (the match counts heights).

- **Space before at a page's top is less the space after that ended
  the page before (2026-10-14).** zh-64044a1d's headings, under
  `w:pageBreakBefore` in mode 14, keep their space at a page's top but
  stand 6pt higher than ours. Labs `hb`..`hm` (`body51.py`–`body53.py`)
  found it by elimination: the grid pitch, settings, Normal's size, the
  default face and language do not move it; the styles part does,
  because the paragraph ending the page before is Body Text, 6pt after.
  Word keeps the space before less that space after: 18pt keeps 12, 9
  keeps 3, 6 or less none, at 12, 16 and 20pt; without the space after
  it keeps all. Ours agrees to 0.1pt in both packages. This is likely
  the "none, half or all" of zh-6d1afa56's headings noted above.
  zh-6d1afa56 16.3% -> 35.9%, zh-64044a1d 27.1 -> 32.9; nothing down.
  Chinese sample 80.0%.

- **`w:mirrorIndents`, built (2026-10-14).** The rule measured below
  is now applied: after paging, a paragraph with the switch that lands
  on page 1, 3, 5… is laid out again with its right indent the left one
  and the first line's, its left the right one and a hanging indent's
  depth, and paging runs again until no paragraph changes side (four
  passes at most; a paragraph is placed by the page it starts on).
  zh-06c46ba9's 687 such paragraphs mostly hang by their left indent,
  where mirroring changes nearly nothing; its 0.7% comes from a blank
  page 2 (task board T10). zh-e27cd8bf 97.0 -> 97.7; nothing else moved.

- **A section of one empty paragraph has a page (2026-10-14).** Lab
  `es` (`body54.py`), in zh-06c46ba9's and zh-9e08ed28's packages,
  six cases each: a section holding only an empty paragraph takes a
  page of its own, left blank, whether the section before ends in a
  text paragraph or an empty one, and two such sections take two
  pages. A page break just before a section's end is that same break:
  the empty paragraph ending the section stays on the page the break
  ends. This replaces the rule above that a lone page break's mark
  holds its page before mode 15 (zh-9e08ed28 is the second case, and
  zh-ae655121's no blank page is the same break), and the old "an
  empty paragraph that only ends a section takes no room" as far as
  pages go. zh-06c46ba9 0.7% -> 47.2% (Word's 72 pages), zh-9e08ed28
  +0.4; bug65649 5.5 -> 3.9, its page 95 now starts as Word's 94 does
  (the page before it already drifts). Chinese sample 80.7%, 58 with
  Word's page count.

- **A picture's line keeps to the line grid in the body too
  (2026-10-14).** Lab `pg` (zh-90e0cea8's own picture paragraph, 25pt,
  on its 15.6pt grid): Word's line is 31.2pt, two such 62.4, and under
  `w:snapToGrid` off 25.5; the picture stands on the line's baseline
  with its mark's descent (3.4pt) under it. The cells-only rule above
  had come from zh-90e0cea8's page foot, which turned out to be drift
  earlier on that page (Word has 12pt to spare there, ours sat 17.6pt
  lower). Text in the lab now within 0.1pt of Word's, pictures 0.8.
  zh-e5709b89 94.2% -> 100%, zh-9c5d0c3f 53.8 -> 55.9 (now Word's 7
  pages); zh-90e0cea8 keeps its score and runs a page long (that
  drift). Chinese sample 80.8%.

- **On Windows, Chinese text falls back to YaHei (2026-10-14).** Left
  to the platform, the engine picks a face per run from its first
  character: a paragraph's ideographs came out in JhengHei UI and a run
  of a lone "〕" in Yu Gothic UI, whose brackets are half an em, so
  lines had room Word's have not. `OfficeFonts` now names YaHei after
  the symbol face, as macOS names PingFang. The Windows box's line
  match (PyMuPDF, `test/docx-line-match.py`) went from 58.8% to 80.3%
  on the sample — within a point of the Mac's from then on.

- **An opening mark a line starts with keeps its blank half
  (2026-10-14).** Without `w:topLinePunct` Word squeezes no opening
  bracket at a line's start. Lab `ls`, printed by Word for Windows
  (`test/docx-word-pdf.ps1`) in 宋体 16pt: "（" and 25 ideographs 4 or
  6pt over break before the last in modes 14 and 15, body and cell,
  indented or not, exactly as a line with no mark does; zh-6d1afa56's
  9pt cells left "公" 1.8pt over for the next line where ours let the
  "《" give. zh-6d1afa56 36.1% -> 41.1%.

- **The mode-15 squeeze test counts the line in its own characters'
  ems (2026-10-14).** The stretch the marks are weighed against is a
  sixty-fourth of an em per gap, and was counted at the size of the
  character being taken. zh-84702a67's 16pt line has twenty characters
  at 10.5pt, and Word takes "“建" 18.2pt over with ）。、， giving 5.5,
  5.5, 3.6 and 3.6 — under the line's own sum, over the 16pt one.
  zh-84702a67 back to 93.3% (the rule above had taken it to 91.1).

- **A merged cell whose rows part over a page is aligned in the rows
  on its page (2026-10-14).** zh-6d1afa56's "工程建设项目招标投标信息"
  is centred and merged over rows 5 and 6; row 6 goes to the next
  page, and Word centres the four lines in row 5. Ours centred them
  over both rows, 40pt low, and two went over the page's foot. The
  text is lifted by what the rows left behind would have given it
  (half for centred, all for bottom), its shading and rules staying
  put (`RichLayout._paginate`, `lift`). zh-232090e0 82.6% -> 93.5%,
  zh-abe7e063 +3.6, zh-90e0cea8 +1.9, zh-e029cf49 98.5 -> 100;
  nothing down. Chinese sample on Windows 81.8%.

- **Symbols are an em wide in a square face (2026-10-14).** In an
  East Asian run, ■□●○◆, arrows and box drawing (U+2190–U+266F) are as
  wide as the face Word sets them in makes them: SimSun (and the other
  square faces Word has) an em — zh-abe7e063's ■□● at 10pt are 10pt
  apart in Word's print — and YaHei its own widths, ○ at 0.6 em
  (zh-457a8d62, zh-7dc3afad). Ours drew them from a Latin fallback at
  0.6 em in every face, so a table cell's line in zh-abe7e063 took a
  character Word wraps. `RichResolvedFace.fullWidthSymbols`, set for the
  faces with no Latin widths of their own. zh-abe7e063 32.8% -> 91.7%
  (Word's 13 pages), zh-232090e0 +2.2; nothing down. Applied to every
  face it took zh-457a8d62 from 95% to 20%. Chinese sample 81.8%.

- **After a line that hangs past the foot, a page break at a
  paragraph's start leaves a blank page (2026-10-14).** Lab `gf`
  replayed in Word for Windows (16pt bold YaHei on an 18pt grid after
  an exact-height filler, then "[break]测试"): with 31.75 to 35pt left
  the line stays, hanging past the foot, and 测试 is on page 3 — the
  break's own line takes page 2 and the break ends it; with 36 left,
  page 2. A break's line otherwise needs no room (lab `pb`: 20pt left
  under a 30pt line, 测试 on page 2 in modes 14 and 15). zh-6d1afa56
  ends a table 28.5pt above the foot, then an empty 14pt paragraph
  (two 15.6pt pitches) and "[break]（五）…": Word's page 23 is blank.
  `overfull` in `_paginate`. zh-6d1afa56 41.3% -> 97.9%, 63 pages as
  Word's; nothing else moved. Chinese sample on Windows 82.7%.
  Seen and not built: in Word for Windows an *empty* line does not
  hang at all (it needs the whole 36, and 31.2 of a 14pt one), where
  the Mac lab `gf` had it hang like one with text.

- **A paragraph of one floating object alone is as tall as its mark's
  line (2026-10-14).** zh-1a3c7aa0's footer holds its page number in
  a text box, anchored in a 9pt run of an otherwise empty paragraph
  whose mark is 14pt. Lab from the document's own package (Word for
  Windows, whose Calibri and SimSun are the Mac's: its print put the
  number at 88.4pt to the Mac's 88.3): the box's text stands 8.4pt
  higher with the 14pt mark than with a 9pt one, and level with a 9pt
  line once the paragraph has a letter of its own. The box hangs from
  the line's top. The mark's look counted for several floating
  objects and now does for one; the footers stand at Word's height.
  The same labs confirmed the reader's rule for a styles part with no
  `w:pPrDefault` (Word spaces it 8pt after, lines of 278/240, exactly).

- **Under odd and even headers, a section numbered afresh opens on its
  number's side (2026-10-14).** Lab `sec`, from the same package: with
  `w:evenAndOddHeaders`, after page "1" a section restarting at 1
  opens on the third page, the second left blank — no header, footer
  or number; after "2" it opens next. After "3" a section from 1 opens
  a page later, one numbered on or from 2 does not; after a page "2"
  (section 1 numbered from 2) a section from 1 follows directly. So it
  goes by the numbers: a first number of the page before's parity
  leaves a blank page between. Without the setting, none.
  `RichLayout._blankPages`. zh-799c91cd 43.2% -> 82.8% (Word's 13
  pages, its page 8 blank). Built in c736c496 together with the rule
  above (a split of the commit that went wrong); the two together took
  the sample on Windows from 83.5% to 84.1%, nothing down.

- **A page break with a section's mark keeps the mark on its page only
  where a line fits (2026-10-14).** "[break]" and the section's mark in
  one paragraph (zh-1a3c7aa0's end of section 1): the mark stays on the
  page the break ends where one line of the paragraph fits there; else
  it takes a page of the section it ends, and the next section opens
  after it. Lab `lb` (the document's package, modes 12 and 15): under
  a filler leaving R points the next section opens on page 2 from R =
  43, page 3 below — whatever the space after; the footer took 27.4 of
  R, leaving one 15.6pt line — and with the paragraph's own exact 28.9pt
  line, from R = 65 and not at 56. The reader folds the break onto the
  next paragraph (`breakEndsPrevious`) and the mark has no height, so
  the line is measured in its look (`_markLineHeight`). zh-1a3c7aa0
  now has Word's pages 10 to 13 (the mark's page 11, the odd/even
  blank 12, the annex from 13): 24.6% -> 29.2%; nothing else moved.

- **On a line grid, a line with none of the tallest stretch keeps its
  own pitches, each stretch centred in them (2026-10-14).** Lab `gc`
  (zh-1a3c7aa0's package, Word for Windows): a chemical name in a
  table cell, its first line all Arial and the rest with YaHei among
  it — Word's baselines 25.0 and then 31.2 apart, a line of 18.1 (the
  1.159 multiple of a 15.6 pitch) and then two pitches. The tallest
  run's strut (02e1c405) held every line to 31.2; left to the engine
  the heights come out right but each stretch's extra height is split
  by its ascent and descent, and YaHei's baseline sat 6pt low. Such a
  paragraph is now laid out with even leading (`_evenLeading`): 25.15
  and 31.2. zh-1a3c7aa0 29.2% -> 70.7% (90 pages, Word's count; its
  annex had run three long). The sweep also carried two of the Mac's
  commits (f67d5ba6, c2542ff6): zh-64044a1d 34.3 -> 65.5, zh-69bbcc3c
  71.3 -> 87.5, zh-15728c84 +1.1 moved with both; nothing down.
  Chinese sample on Windows 86.4%. Not understood: the same paragraph
  justified in the body, first on its page, still comes out 28.55
  apart in ours (another path lays it out).

- **What opens a line and gives some of itself there stays off the
  line before (2026-10-14).** The fitter plans zh-89385c94's cell
  lines as Word sets them — "核清查及追蹤管" and then "考，並研提興利防弊",
  0.55pt over with its comma giving 0.57 — but the narrowed "考，" then
  fitted the line before, and the engine took it there. The line
  before's last character is now widened by the difference and a
  quarter point (the planned line had the room). Lab `hc` (the cell
  alone): ours line for line as Word's. zh-d68ac84a 43.5% -> 81.4%,
  zh-e6d54ae4 52.8 -> 64.6, zh-64044a1d 65.5 -> 73.8, zh-89385c94
  +0.5; zh-9e08ed28 60.0 -> 50.0, though its cell "財產局)、財政部(關務署)"
  now breaks as Word's where it had not: the row is a line taller, as
  Word's is, and the pages after it part from Word's at the next cell
  that breaks elsewhere — Word ends a line with a half-width "(" before
  an ideograph ("內政部(" / "警政署)"), which ours keeps with it. (The
  sweep carried f774a736 too.) Chinese sample on Windows 87.1%.

- **In a table cell, a paragraph's last mark gives its half before
  2013's layout (2026-10-14).** Under Taiwan's Chinese a closing mark
  ending a cell's line keeps its width before mode 15 — not the
  paragraph's own last mark. Lab `pe` (zh-89385c94's package, Word
  for Windows): eight ideographs and ，。）」、； are taken up to 7.0pt
  over at 14pt and not at 7.5 where they end the paragraph, and not
  even 0.55 over where text follows. zh-89385c94 53.3% -> 99.3%,
  zh-9e08ed28 50.0 -> 84.7, zh-06c46ba9 +6.6, zh-e6d54ae4 64.6 ->
  82.7 with the next rule. Down: zh-64044a1d 73.8 -> 68.0, a line now
  taken on a row whose third column starts 3.6pt left of Word's (a
  table of percentage widths laid out automatically: T1).

- **What of a parted row goes over is as tall as a merged cell's text
  that went with it (2026-10-14).** zh-e6d54ae4's "（三）注重服務人員…" is
  merged over two rows and the second parts over the page; the part
  that goes over was as tall as its own one line, not the merged
  cell's three carried beside it, and the next row stood over them.
  A whole row at a page's top already counted such a cell
  (`pageHeight`); a parted row's part now does. Chinese sample on
  Windows 89.2%.

- **The engine's cache of shaped paragraphs ignores where the leading
  goes (2026-10-14).** The even-leading layout of 21d7c218 came back
  proportional for every paragraph but one laid out after a different
  one: skparagraph's `ParagraphCache` tells text styles apart by
  `equalsByFonts`, which never compares the half-leading flag and
  takes heights a 4096th apart as one, so the paragraph's own
  proportional layout, made first, was served again. Neither a height
  a millionth more nor a root style's height (the bridge does not
  carry it to the key) missed it; a font feature no face has
  (`zevn`), which shaping ignores and the key compares, does. Labs
  `gc`/`gc2`/`gcs`: every such paragraph 25.15 then 31.2 apart, as
  Word's 25.1 and 31.2; zh-1a3c7aa0's chemical names within 0.2pt.
  Anything else that sets `leadingDistribution` on a text style meets
  the same cache.

- **A line may break before a hyphen after an ideograph (2026-10-14).**
  zh-1a3c7aa0's chemical names in a 128pt cell: Word sets "异佛尔酮二胺；
  3,3,5-三甲基" and "-4,6-二氨基-2-烯环己酮；1-", the "；" giving 3.5;
  the engine will not break before "-" (UAX 14 keeps a hyphen-minus
  with what precedes it), so "基-4,6-" went over whole and every line
  of such a name was a character short. A zero-width space now stands
  there (`_breaksBetween`). zh-1a3c7aa0's annex cells break as Word's
  (its score moves little: the lines were at the right heights); the
  pattern is in no other document of the sample.

- **Charts are drawn (2026-10-14).** A chart in a .docx (`c:chart` in a
  drawing) was kept as an empty box of its size. Its part is now read
  as Slides reads one (`ChartXML.read`, against the document's theme)
  and drawn by Slides' painter, with the chart area's own fill and
  border, through a hook the layout calls for an object it cannot draw
  (`RichLayout.objectPainter`; `drawsObject` lets such an object float
  and be wrapped round as a picture is). `WriterCharts`. 61745 (two
  charts and nothing else) 0 -> 15 of Word's 17 lines; zh-37b6536f
  30.8% -> 96.2%, its page-3 pie now where Word's is and the text
  below it. Not yet: Word 2016's `cx:` charts (chartex), and a pie's
  automatic title ("Series 1" where Word's print says "Chart Title").

- **No ligatures (2026-10-14).** Word sets a face's ligatures only
  where a run asks for them (`w14:ligatures`); ours took Carlito's "ti"
  and "tt", narrower than the letters, and "Section" in Headers came out
  of the PDF as one glyph. Writer now sets letters one by one, as
  Slides does (`RichTextTheme.disablesLigatures`). POI set on Windows
  67.1% -> 69.7% with the charts: Headers, 59030 and TestTableCellA
  -> 100%; nothing down. Chinese sample 90.6%.

- **A text box takes its room as a floating picture does
  (2026-10-14).** bib-chernigovka's cover title is a 475 by 376pt text
  box wrapped square, wider than the column: Word sets the paragraphs
  after its anchor below it, the year at the page's foot and the
  calendar from page 2. Ours wrapped round pictures and charts only, so
  the year stood under the anchor and the calendar began on page 1.
  Word for Windows prints the cover as ours now does (the year at 97.5pt
  above the foot, ours 95); Word for Mac's print has the whole page 21pt
  lower, which neither page border nor anything else in the lab
  explains. No document moved by 0.3% either way.

- **A header or footer with a tab is the file's, not the editor's line
  (2026-10-14).** A kept header or footer whose text held a tab was
  drawn as the editor's plain line (12pt, no rules, its other
  paragraphs gone), from before the kept paragraphs had their styles'
  tab stops; and the reader dropped `w:ptab`, a positional tab, so
  "VDPAM 527_S. Azeem_HW13" ran into "Page 1 of 14" (bug57031). Both
  now as the file has them: a positional tab is a tab, placed by the
  Header and Footer styles' centre and right stops. POI set on Windows
  69.6% -> 70.8%: FancyFoot, ThreeColFoot, SimpleHeadThree,
  ThreeColHeadFoot, DiffFirstPageHeadFoot -> 100%, PageSpecificHeadFoot
  80 -> 90, bug57031 +4.1; zh-90e0cea8 67.1 -> 86.2; nothing down.

- **A `c:` chart's column value labels and category labels stand higher
  in Word (2026-10-18, T113).** zh-547fc43c's charts print them 2.4 to
  2.8 pt over ours at 10 pt Calibri and 3.2 over at 10.5 pt 宋体; they
  now stand a quarter of their size higher, 0.3 in a square East Asian
  face (`Chart._wordLabelRise`). The Windows box's lab (the first chart
  alone, its faces swapped) shows Word setting 宋体, 黑体 and Calibri
  within a fifth of a point of one another — only 微软雅黑's tall line
  moves them — so the larger step is our stand-ins' (宋体's digits in
  Liberation Sans, Calibri's in Carlito), not Word's. Not chartex's `cx`
  charts (their years already stand where Word's do), not on a slide.
  zh-547fc43c 96.8 -> 98.2; the five other documents with charts
  unchanged. Then only where the chart's text is marked Chinese,
  Japanese or Korean (`lang` on its runs, `Chart.eastAsianText`):
  chartex's own `c:` charts (no lang) had their category labels at
  347.35 for Word's 347.76, and the raise took them to 345.1 — inside
  the line match's 3 pt, so its score never showed it (the Windows
  box's other session asked). zh-547fc43c's runs say zh-CN, and the
  lab kept that lang when it swapped the faces.
- **Word 2016's charts show as their pictures; a chart in a line is
  drawn (2026-10-14).** A `cx` chart (box and whisker, waterfall …)
  comes as `mc:AlternateContent` whose Fallback is a picture of it:
  the reader took the Choice, failed on it, and the chart took no room
  — chartex printed on one page to Word's three. The Fallback's picture
  is now shown. And a chart in a line with text (chartex's line chart,
  a space after it) went through the inline path, which never asked
  `objectPainter`: drawn now too. chartex has its three pages; its
  radar chart stays a grey box (Slides reads no radar charts).
  (Its line match fell 12.5% -> 6.9%: the charts' own labels stand a
  few points from Word's, where before, with no charts, unrelated lines
  happened to meet.)

- **A picture on the first line of several keeps to the grid
  (2026-10-14).** The snap of a picture's line (cab83667) was for a
  paragraph of one line. zh-9c5d0c3f's fifth column holds its sign, a
  break and its caption in one paragraph; Word stands the sign level
  with the other columns' on their 90pt lines, ours 9.7pt higher. Now
  the first line is snapped the same way — on its baseline, the text's
  descent under it (taken from the caption's line: the picture's own
  has none) — and the sign is within 2pt. zh-9c5d0c3f +1.0,
  zh-37b6536f +0.7; nothing down.

- **Cell spacing (2026-10-14).** `w:tblCellSpacing` was read and not
  laid out. Lab `cs` (Word for Windows, one-line rows at s of 0, 0.75
  and 5pt): each row is 2s taller, the first row's text 2s down, the
  table 2s longer under its last row, the first column's text 2s and
  the others' s to the right — s round every cell and s more at the
  table's edges, which is how the cells are padded now. Ours matches
  each delta to 0.3pt. zh-9c5d0c3f 55.1% -> 65.3% (its road signs
  gained 1.5pt a row), bug57031 14.7 -> 24.5; the four documents that
  use it are those two, bib-chernigovka and drawing. (The sweep also
  carried 2058f789 and 03f1e859; zh-7dc3afad 98.5 -> 92.9 and
  zh-8e8d4c40 -1.7 moved with those, not with this.)

- **A row with nothing left for the next page goes over whole
  (2026-10-14).** A row that does not fit was parted wherever each
  cell had a line that did; where every cell then ends on this page —
  only the row's own height, its space after and margins, over the
  foot — Word parts nothing and takes the row to the next page.
  bug59058's yearly rows (one centred line and 14.4pt after it in each
  cell) were squeezed into the 33.8pt left at page 2's foot. Not for a
  row with a cell merged down from above or into the rows below:
  zh-e6d54ae4's such row parts at the foot as Word parts it (82.7%
  fell to 43.2 without that).

- **A paragraph's one line is no orphan (2026-10-14).** Widow and
  orphan control took a paragraph that starts at a page's foot back to
  the next page where fewer than two of its lines fit — counting a
  one-line paragraph whose line fits and whose space after does not.
  bug59058's thirteenth empty paragraph under a table, 15.4pt of line
  in 17.3pt, stays at page 3's foot in Word; ours moved it and set
  page 4 26pt low. Now only a paragraph whose lines go on is held back
  — and any picture's paragraph, whose cuts are its empty line's, not
  the picture's (bug57031's 360pt chart otherwise started at page 1's
  foot). Bug51170 32.5% -> 78.5, bug65738 65.2 -> 69.6, bug59058 +1.1.

- **A multiple on a picture's line adds to the mark's line, below
  (2026-10-14).** Lab `hp` (Word for Windows: Bug51170's 78pt logo alone
  in a header paragraph, Calibri 11): the paragraph after it stands
  2.04pt lower at 1.15 lines than at single and 13.44 lower at double —
  0.15 and 1 of Calibri's 13.43pt single line, not of the picture —
  with or without text beside the picture, in modes 11 and 15. A
  picture-only line has no descent under it; with text it has the
  text's single descent. The engine lost the multiple under the
  picture (nothing added alone, the descent scaled with text). Now
  `(multiple - 1)` of the mark's single line goes under such a line.
  Every page of Bug51170 under its header had stood 2pt high.

- **Word kerns only where `w:kern` says (2026-10-14).** A run is kerned
  from the size its `w:kern` names up, and not at all without one; the
  engine kerned every pair. bug59058's Calibri 12 abstract, unkerned,
  is word for word Word's widths ("Abstract" 40.99, kerned 40.55), and
  its Times New Roman bold caption no longer fits "State," where Word's
  line ends "Women by" ("Wo" alone kerned 0.67pt).

- **An autofit table keeps a grid wider than the width it states in
  points (2026-10-14).** As it does one wider than its share
  (zh-06c46ba9, above): bug59058's centred article table says 552.75pt
  over a grid of 553.5, and Word centres the grid, its text 0.39pt left
  of ours on every line. With kerning gone that was enough to carry
  "logistic" to the next line of page 6 and every page after it.

- **Aptos keeps its own line (2026-10-14).** It is drawn as the sans
  clone, whose line is 1.15 ems; Word's Aptos line is 1.22, its
  baseline .94 down (lab `ap`, Word for Windows: 12pt lines 14.64
  apart, the first baseline 11.28 under the margin). table-alignment's
  empty paragraphs between its tables were each 2pt short.

- **A header or footer of type "odd" is the default one
  (2026-10-14).** The format has no such type; Word prints 60293's
  "ODD_PAGE_HEADER" on its third page, where ours had none.

- **A tab keeps its stop in a justified line (2026-10-14).** The
  engine's justifying sets every whitespace character of a line to its
  one step, the tab's widening (`tabs`) with it: bug65649's numbered
  clauses ("1.1.<tab>По Контракту…", a stop at 1418 twips) started
  their text 15pt short of the stop wherever the line was justified,
  and at it where the line ended in a break. Lab `tj` (Word for
  Windows): the text is at the stop justified or not, in Latin and
  Cyrillic. A widened tab in a justified paragraph is now set as a held
  space — a no-break space as wide, a zero-width space after it for
  the break.

- **A table's columns are whole pixels from a hair over (2026-10-14).**
  63.5pt is 1270px at the print's scale, which 4/3 times 15 makes
  1269.9999…, and flooring lost a pixel: bug57031's autofit column,
  exactly as wide as "Transform" in its cell (55.99pt in 56), wrapped it
  — and "[Lower" in the next table — once kerning stopped saving the
  twentieth of a point.

- **A justified line's spaces give for a word only up to half their
  stretch (2026-10-15).** From mode 15 a justified line takes a word
  that is over by squeezing its spaces, to three quarters of their
  width at most (lab `js`, above). That is not the whole rule: the
  word is taken only where each space gives no more than half of what
  each would stretch were the word left for the next line. With n
  spaces, the word C over and E to spare without it: C/n <= E/(n-1)/2.
  Lab `jg` (Word for Windows, Times New Roman 12, a last word of 3 to
  28pt after 8 and after 16 spaces): "x" is taken 3.1pt over, "xx"
  5.2, "mmm" 10.7, all to the lab's tenth of a point, and so are lab
  `jt`'s lines of "ab", "abcd" and longer words. Mode 14 squeezes
  nothing. The squeeze was in the East Asian fitter only; it now runs
  for every justified paragraph from mode 15, and the fitter takes
  Greek and Cyrillic words whole (each letter of bug65649's Russian was
  a stretch of its own, so a word over looked like a letter over).

- **A cell centres its text with the boxes floating from it
  (2026-10-15).** A text box anchored in a cell's paragraph (wrapNone,
  in the cell) counts toward the content the cell centres, to its foot
  and its effect extent's: zh-454e2e29's two exact 18pt lines with
  "娩假 42日" (37.75pt, 4.35 into the first paragraph, 1.25 of effect
  below) stand 4.3pt from the 51pt row's top in Word's print — a block
  43.35 tall, not the lines' 36 — and the next row's 3.4 for a box that
  reaches 44.65. Ours had centred the lines alone, 3.5pt low.
  zh-454e2e29 48.4% -> 54.2%; nothing else moved.

- **Two lines in one (2026-10-15).** A run with `w:eastAsianLayout
  w:combine` is set as two lines at half its size, the first half of
  its text over the second, the pair as tall as a line of the run's
  own size and standing where one would. zh-454e2e29's table title
  combines "機關名稱機關代號" and "公務人員醫事人員" at 24pt: in Word's
  print two 12pt lines 20.64 apart, 48pt wide, the upper's baseline
  15.12 over the line's. Ours set them flat, the title took two lines
  and its row ran 34pt tall; now the box of two lines stands before the
  run (one more character in the painter's text, as an insert) and the
  run's text is kept, hidden — the half lines land within 0.07pt of
  Word's. On the line grid the line is as many pitches as the box
  needs, centred in them as text is (three 18pt pitches here).
  zh-454e2e29 54.2% -> 71.9%; nothing else moved by it.

- **A small table in a cell is a table (2026-10-15).** Nested tables
  were flattened into their cell, by design: the layout knows one level
  of table. zh-454e2e29's nested forms ("姓名 | 職稱 | 職務編號 | 考績等次 |
  未報送考績原因" over two empty rows) stood as a column of lines 36pt
  apart. A nested table with none in it, of 15 rows and 600 characters
  at most, is now read as a document of its own and set in its cell as
  a block (a `RichTextBox` that `growsToFit`, laid out by a layout of
  its own, with the tables' looks and grids and the page's line grid),
  its markup kept for the save. Longer ones are still flattened: a
  block does not part across pages, and 60329's protocol text — 2,235
  characters in a three-row table in a cell — ran to six pages that
  way. The block keeps off the line grid (it is no line).

- **A sign's hyphen may end a line (2026-10-15).** Word parts a line
  after a hyphen-minus that opens a word and a digit follows; the engine
  keeps "-0.01" whole. bug59058's page 9 table text ends a line " -"
  and starts the next "0.01". A zero-width space now stands after such
  a hyphen outside East Asian layout (the sibling rule for "КС-2" and
  "2024-10", lab `hy3`, stops there too: zh-64044a1d's "0932-757839"),
  and the fitter knows both breaks.

- **A picture's line keeps to the grid under "at least" too
  (2026-10-15).** The rule that snaps a picture's line to the line grid
  (as many pitches as the picture and its mark's descent need, the rest
  above) passed over any paragraph that states a line height. Word
  passes over an exact one only: zh-9c5d0c3f's fifth column, a 58.5pt
  sign in a paragraph of at least 19.2pt on an 18pt grid, takes four
  pitches in Word's print with 7.5pt over the sign; ours set it flush
  and its captions 14pt high. zh-9c5d0c3f 65.3% -> 81.6% (page 4: 4 ->
  21 of 22 lines). Still open on its page 5: a 69.8pt sign under the
  same spacing takes no fifth pitch in Word (3.4pt over it, not 14.7).

- **A section of columns before a continuous one is a row
  (2026-10-15).** The layout has one column count for the whole
  document, so a section of columns that a continuous section follows
  on the same page — its columns filled by column breaks — took a page
  a column. Such a section is now read as a row of a borderless table:
  a cell a column, the gaps as columns of their own, widths from its
  `w:cols`. The section's end stays a top-level paragraph, empty (it
  takes no room, as an empty section end takes none in Word — a copy of
  zh-a0e932c2's in the last column had set what follows 12pt low), so
  the sections count as before; the markup is kept and written back
  (`KeptTable`, id "kc…") while the text is unchanged. zh-a0e932c2's
  "12 | 大肠菌群 | GB 4789.3 大肠菌群平板计数法": 22.6% -> 100%, Word's 5
  pages; zh-6cd1befe's "附件3" beside its title: 85.2 -> 93.3, Word's 59
  pages. Chinese sample 92.91 -> 94.2. A section of columns over whole
  pages (zh-6cd1befe's seventh) is still set in one column.

- **A mark hangs to its em and not a hair past; an indent in
  characters is whole twips (2026-10-15).** Lab `hc` (Word for Windows,
  zh-d68ac84a's grid — 16pt on `linesAndChars` at -5544, a 439.4pt
  column — a first-line indent then 28 ideographs and "。"): at 586
  twips of indent, or 200 hundredths of a character, the mark would end
  0.003pt past its em of hang and Word wraps "献。"; at 580 it hangs.
  Ours allowed the hang a 0.005pt hair and took 200 hundredths as
  29.293pt; now the hang has no hair and a character-counted indent
  (first line, left, right) is rounded to twips, as Word keeps it (586,
  29.3). The lab matches Word in all five of its indents; zh-d68ac84a
  81.4% -> 83.8% (its page 22 "…计算地方综合贡献。" wraps "献。" as
  Word's does). Rounding every grid character's width to twips instead
  was tried and was worse (75.6%).

- **On a character grid a line is squeezed only to the half em, not a
  hair past (2026-10-15).** The fitter takes the next character where
  the line's marks can give what it is over, up to half an em, with a
  tolerance of 0.045pt: off a grid, Latin text on the line makes our
  sum differ from Word's by hundredths (zh-a4b0f6ea's "《威"). On a
  character grid every width is the grid's — digits too — and ours
  are Word's to the ten-thousandth: zh-d68ac84a's "（3）合理性审核…价格
  是" is 7.3248 over against a half em of 7.3232, and Word ends the
  line at "格", justified (14.92 a character), where ours took "是".
  The tolerance now stands only for a line off a character grid.
  zh-d68ac84a 83.8% -> 99.2%; nothing else moved. (T12.)

- **Under `w:kinsoku` off a mark is a piece of its own to the fitter
  (2026-10-15).** `_span` lets such a paragraph start a line with a
  closing mark and end one with an opening mark (2058f789), but the
  fitter still glued "目，" into one piece, so its lines ran a piece
  behind the engine's: zh-9e08ed28's cell line "，以落實成效。" is 0.5pt
  over and taken in Word (the "，" gone down from "目"); ours sent the
  "。" down alone. The mark is now judged alone, as the Mac's T16 lead
  on zh-799c91cd's "各執1份為憑。" asked. zh-9e08ed28 85.4% -> 91.2%,
  zh-799c91cd 92.0 -> 97.6; nothing else moved. Chinese sample 94.6.

- **In a cell a line's last bracket gives its half before 2013's layout
  (2026-10-15).** The rule that the line's last mark keeps its em in a
  cell before mode 15 (zh-TW; measured with a comma) held for every
  closing mark. Lab `cb` (zh-9e08ed28's package, Word for Windows, a
  97.5pt cell, a line 0.5pt over): "…服務團」", "…團）", "…團』" are taken,
  "…團，", "…團。", "…團、" go down — Taiwan's faces centre "，。、；：！？"
  in their em, which leaves them no blank half to give; a bracket has
  one. The rule now keeps only those centred marks. The lab matches
  Word line for line; zh-9e08ed28 91.2% -> 99.6%, zh-89385c94 99.3 ->
  99.8; nothing down. Chinese sample 94.73.

- **The mark before a line break gives as a paragraph's last does
  (2026-10-15).** In a cell before mode 15 a line's last centred mark
  keeps its em unless it ends the paragraph (lab `pe`); a mark before a
  line break (`w:br`) counted as one with text after it. Text after a
  break is on another line: zh-e6d54ae4's cell line "…皆設有免費無線上網
  服務。" before its break is taken 8.2pt over in Word, its "、" and "。"
  each giving half; ours sent "務。" down. zh-e6d54ae4 82.7% -> 93.5%;
  nothing else moved. Chinese sample 94.89.

- **A VML rectangle has its stated size, and a horizontal rule is a
  line (2026-10-15).** The reader took a VML shape's size from its
  style only on `v:shape`; a `v:rect` fell to the 300 by 200 default.
  An HTML page's `<hr>` comes into Word as such a rect, `o:hr="t"`,
  "width:0;height:2.25pt", across the column: bug57031's SAS output
  has one before each table, each a 200pt box that pushed a page on,
  and drawing.docx is full of them. `v:rect`, `v:roundrect` and
  `v:oval` now read their style too, and a rule is its height and no
  width (its gray line is not drawn yet). bug57031 49.9% -> 74.6%,
  drawing 3.0 -> 41.0; POI 74.39 -> 75.0, nothing down.

- **A horizontal rule's paragraph is a line of its text (2026-10-15).**
  Lab `hr` (Word for Windows, Arial 10, rules of 1.5, 2.25 and 6pt):
  each rule's paragraph is one 11.5pt line of its text whatever the
  rule's height, the rule drawn across its middle. Ours gave the
  paragraph the rule's own height, a paragraph of one object being set
  as the object. A rule (the reader's "hr") now takes its mark's line,
  and in a line of text keeps the line's strut. The lab matches Word to
  0.06pt; bug57031 74.6% -> 87.3%, drawing 41.0 -> 66.5; POI 75.0 ->
  75.36, nothing down.

- **Verdana keeps its own widths and line (2026-10-15).** Its stand-in,
  DejaVu Sans, is a few per cent wider in its letters (a .613 em to
  Verdana's .601) and narrower in its space (.318 to .352), and its line
  is 1.164 ems to Verdana's 1.2153. drawing.docx's Verdana 9 Russian
  news held a word a line fewer, every page running on. The stand-in is
  now set to Verdana's own advances — U+0020 to U+007E, Latin-1,
  Cyrillic and the common punctuation, regular and bold, read from
  Windows' verdana.ttf and verdanab.ttf — and Verdana's line (hhea
  ascent and descent, no gap; baseline 1.0054). drawing 66.5% -> 89.9%;
  Chinese sample 95.69 -> 95.83 (zh-abe7e063 91.8 -> 98.4, four more up
  a little), POI 75.36 -> 75.59; nothing down.

- **The mark under a nested table takes no room (2026-10-15).** A cell
  must end in a paragraph, so one that ends in a table has an empty
  mark under it, and Word gives that mark nothing — no line, no
  spacing — and the table itself no paragraph spacing. bug65738's cell
  of a two-row nested table ends 2.75pt (its margin) under the table in
  Word's print; ours set the table's paragraph 10pt after and the mark
  a line and 10pt more under it, 37pt in all. Labs on its package (Word
  16): with "after" typed into the mark the row grows by that line and
  its spacing (26pt); in compatibility mode 15, with a stated cell
  spacing of 0, or at a width in fiftieths the mark still takes
  nothing; and drawing.docx's 8.5pt mark under its own nested table,
  set at 50pt, moves nothing. Both now take no room in the layout (the
  file keeps them). bug65738 69.6% -> 100%; Chinese sample 95.83 ->
  95.99 (zh-4b8e0abc 89.2 -> 96.6, zh-84702a67 93.8 -> 96.9); POI 75.59
  -> 75.82. drawing 89.9 -> 80.8: its "12.04.2006 - Cbonds" row stands
  in HTML tables nested three deep, flattened into their cell without
  their margins and spacing — Word indents it 13pt and sets it 41pt
  under the line above where ours, without the mark's line to make up
  for them, now has 30.

- **The row above's bottom line lies in the cell's top margin
  (2026-10-15).** A row is as much taller as the line above it is wide
  — where its cells, or the table's inside lines, say that line. Where
  only the row above rules its bottom, Word sets that line in the lower
  cell's top margin and gives it only what of its width the margin
  does not hold. Lab `bm` in table-indent's package (Word 16, 12pt
  Times rows of 18.4pt): under a 1pt line, rows 19.4 apart with no
  margins, 21.1 with 55 twips above (none below), 22.1 with 55 twips
  below (none above), 19.9 at 10 twips each, 22.4 under a 3pt line at
  20 twips; and 20.4 at 10 twips where every cell rules its own top. A
  table's top and bottom lines take their full width as before.
  table-indent's cells rule their bottoms alone over 55-twip margins,
  and its rows stood half a point too far apart: 50% -> 100%. POI
  75.82 -> 76.30; the Chinese sample unchanged (95.99).

- **A piece that opens its line may hang its mark (2026-10-15).** The
  fitter judged what comes next on a line only where something stood
  on the line already; a stretch that opens the line and is itself too
  wide was left to the engine, which broke it wherever it ran out —
  between "）" and "。" too. zh-69bbcc3c's form leaves its blanks as
  paragraphs of spaces: 48 spaces and "）。", 416pt in a column of
  415.6, are one line in Word's print, the "。" 0.4pt past the margin.
  Such a stretch now hangs its last mark as any other. Chinese sample
  95.99 -> 96.20 (zh-1a3c7aa0 72.9 -> 86.3, zh-69bbcc3c 89.4 -> 90.6);
  POI 76.30 -> 76.78 (SampleDoc 50 -> 100, the Mac's Arial Black in
  the same sweep); nothing down.

- **An opening mark keeps its spaces and what follows them
  (2026-10-15).** The same form writes its blanks as "（   ）": an
  opening bracket, spaces, a closing one. The engine may break after
  spaces, so "（   " was a stretch of its own, and a line could end on
  "（" — which no line may. Word keeps "一般项（   ）" whole at a line's
  end, its five marks giving 4.9pt each and the "）" hanging; ours set
  "）" a line down. An opening mark's trailing spaces now bind it to
  what follows them. And a stretch that opens its line squeezes its
  own marks as well as hanging one (above): "       ），" after a 344pt
  first-line indent, 4.25pt over, is one line in Word's print, the "）"
  4.3pt close. zh-69bbcc3c 90.6% -> 90.7 (its page 17 whole); nothing
  else moved.

- **An autofit table keeps a grid one margin wider on each side
  (2026-10-15).** A table of no stated width that Word fitted to the
  column is saved with a grid as wide as the column and its cells'
  side margins — it stands out by a margin on each side. Ours scaled
  any grid wider than the column down to it, so every column of such a
  table came out a margin's share narrower: zh-69bbcc3c's plan tables,
  708.7pt in a column of 697.9 in Word's print, wrapped "序号" at 15pt
  in a cell of 29.4. Twenty-one tables in ten of the corpus' documents
  are 1.9 to 10.8pt over in this way; such a grid is now kept (wider
  still, it is scaled as before — none in the corpus is). Chinese
  sample 96.21 -> 96.69: zh-8e8d4c40 87.1 -> 98.9, zh-7dc3afad 93.1 ->
  99.0, zh-69bbcc3c 90.7 -> 98.2 (two of its cells by the Mac's
  a5508aca, in the same sweep), zh-5901e2b0 97.1 -> 100, zh-a4b0f6ea
  84.6 -> 88.3, zh-06c46ba9 +0.6, zh-84702a67 +0.4; POI 76.78 ->
  76.82 (Bug54849 91.3 -> 95.7); nothing down.

- **In a cell too a stretch that opens its line is fitted
  (2026-10-15).** The rule above let a line-opening stretch hang its
  mark — but in a cell nothing hangs, so such a stretch was still left
  to the engine. zh-69bbcc3c's transfer form has a cell line of a 317pt
  first-line indent, 14 spaces and "）。", 9.85pt over its column; in
  Word's print it is one line, the "）" 3.8pt close and the "。" giving
  its blank half past the edge, as the marks of any line give. Now the
  stretch's own marks give there as anywhere. zh-69bbcc3c 98.2% ->
  99.8, zh-64044a1d 90.4 -> 92.0; Chinese sample 96.69 -> 96.74; POI
  unchanged.

- **`w:splitPgBreakAndParaMark`: the mark after a page break goes to
  the next page (2026-10-15).** A paragraph that ends in a page break
  leaves nothing on the new page in Word 2013's layout (SampleDoc), and
  the reader drops its mark. Files that carry this compatibility switch
  before that layout — zh-64044a1d (mode 11), 60329, zh-8c2948a8 and
  zh-8cd03691 (mode 12), and several of no stated mode — have Word
  carry the mark over: zh-64044a1d's annexes each follow a paragraph
  of a page break alone, and Word's print opens their pages with its
  empty line, the heading 36pt down. The reader now keeps the mark as
  an empty paragraph after the break there. The save writes a file of
  2013's layout, where that paragraph is the same empty line.
  zh-64044a1d 92.0% -> 92.8; nothing else moved by it (the sweep also
  carried the Mac's b18da088 and 95d61f1d: bib-chernigovka 0 -> 91.7,
  zh-15728c84 91.5 -> 94.0).

- **A cell's own margins (2026-10-15).** The reader kept a cell's
  `w:tcMar` for the save only; the layout set every cell at the
  table's margins, or at those most of its cells carry. zh-6cd1befe's
  list of emergency departments narrows a few cells' margins to 51
  twips where the table says 108, and "生物灾害指因病" at 10pt fills
  their 70.5pt lines in Word's print; ours held six characters. A cell
  that states margins now has them, over the table's. zh-91e44bcb 95.7%
  -> 96.4, zh-37b6536f 96.9 -> 97.7; zh-6cd1befe's page 48 rows as
  Word's, the last one then ending beside its footer's page number
  (next entry).

- **A footer's frames that stand above it keep the body clear
  (2026-10-15).** A footer's framed page number floats: it takes no
  room in the footer, and stands where the frame says from the text it
  is anchored to. zh-6cd1befe's stands 11.75pt above the footer's
  empty paragraph (`w:y="-235"`), and in Word's print the body ends
  above it: page 48's last row, which would end beside the number,
  opens page 49. The body's foot now clears what a footer's frames
  rise above its first line, up to 36pt (a frame far up the page Word
  wraps the body round, which this does not model). With the cell
  margins above, zh-6cd1befe 93.3% -> 97.0; Chinese sample 96.79 ->
  96.87 over both (the Mac's commits of the same sweeps aside); POI
  unchanged by either.

- **In the squeeze test a Latin run is one character (2026-10-15).**
  From 2013's layout on a justified line takes the next character where
  its marks give less, as a share of their halves, than the line would
  stretch, as a share of a sixty-fourth of an em at each of its gaps.
  The line's characters were counted one by one, digits too. Lab `dg`
  (Word 16, mode 15, SimSun 16pt, no automatic spaces, in
  ~/starling-doc-check/lab/dg): a line of 15 ideographs, two commas
  among them, and "1234" and "5678" takes the next ideograph 12.6pt
  over and not 12.8, where 23 ideographs take it 11.8 and not 12.0 —
  each digit counted as a character would stop it at 11.9. Counted as
  one character of the run's em, a Latin run gives both. (Set left,
  neither line takes anything, even 2pt over, as the code has it.)
  zh-457a8d62's "…之女104年10" now takes "月" 12.86 over as Word does:
  94.7% -> 95.1; nothing else moved. Still open: with the automatic
  spaces on (lab `dg5`, the same line, a quarter em at each of the four
  boundaries) Word takes the ideograph 9.0pt over and not 9.5, where
  ours takes it to 13 — before this change and after; and
  zh-457a8d62's "35筆…都更案)，" (a character grid, automatic spaces)
  leaves "經" 12.44 over, which this now takes.

- **A Latin comma hangs at a line's end (2026-10-15).** In a justified
  paragraph of East Asian layout, from 2013's layout on, a line may end
  with a Latin comma past the margin, all of it. Lab `hc2` (Word 16,
  mode 15, Cambria 14, ~/starling-doc-check/lab/hc2): "…di karantina
  pusat," is taken 9.5pt over and not 10, "…pusat" without the comma
  7.0 and not 7.5 — the comma's 2.87 the difference; the spaces give
  the rest. zh-4b8e0abc's Indonesian answer ends "pusat," 2.7pt past
  the margin in Word's print, where ours left the word for the next
  line and its page ran a line long. (That lab also finds the line's
  seven spaces giving about a third of each, 7.0 and not 7.5 — more
  than the quarter lab `js` measured — and the colon in "kesehatan:"
  half a point; not built.)

- **A line's automatic spaces are stretch too (2026-10-15).** The test
  from 2013's layout on weighs what the marks give against what the
  line would stretch, a sixty-fourth of an em at each gap; the
  automatic spaces between ideographs and Latin gave half of themselves
  to the room but nothing to the stretch. Lab `dg6` (Word 16, mode 15,
  SimSun 16pt, justified, a quarter-em space at each digit boundary):
  two commas and four spaces take the next ideograph 9.0pt over and
  not 9.5; two spaces 10.0 and not 10.5; four commas 10.5 and not 11;
  eight spaces 7.5 and not 8; one comma 7.0 and not 7.5; no mark 4.5
  and not 5. Ours took them all to 13. Counting the line's automatic
  spaces whole in its stretch matches 124 of the lab's 126 lines (two
  stop half a point short). On a character grid the digits carry the
  grid's room and no such space, so zh-457a8d62's lines are as they
  were. With the comma above: zh-4b8e0abc 96.6% -> 99.6, zh-84702a67
  97.3 -> 98.2; Chinese sample 97.03 -> 97.09; POI unchanged. (Alone,
  zh-4b8e0abc's "同" went down a line as in Word's print, onto a page
  already a line long — 89.7 until the comma.)

- **A picture paragraph's picture stands where the paragraph aligns it
  (2026-10-15).** A paragraph of one picture is the editor's picture
  paragraph, and its picture was set at the text's left whatever the
  paragraph's alignment. zh-9c5d0c3f's road signs are centred in their
  cells in Word's print (jc center), at the cells' left in ours. A
  picture now stands centred or to the right as its paragraph says
  (one wider than its line keeps to the left). No text line moves by
  it.

- **Before 2013's layout a spaced table is set out by its first cell's
  text inset (2026-10-15).** There the indent is where the first
  column's text starts, so the table's edge stands that cell's whole
  inset to the left: its own margin (`w:tcMar` over the table's), the
  cell spacing twice and half its side line. Ours set it out by the
  table's margin alone. zh-9c5d0c3f's road signs (mode 12, -685 twips,
  15-twip spacing over cells of 60-twip margins, 0.75pt lines) stood
  4.5pt right of Word's print and now 0.4; bug57031's "Note:" table
  (no lines) puts its text at 72.0, the margin, as Word's does. Only
  tables that state a spacing, the two of the evidence; no document
  moved by 0.3.

- **A picture's line on the grid is as many pitches as the picture is
  tall (2026-10-15).** Not its mark's descent with it, as ours counted.
  Lab `pg2` in zh-9c5d0c3f's package (Word 16, mode 12, an 18pt line
  grid, ~/starling-doc-check/lab/pg2): a sign 54pt tall takes three
  pitches, 57 to 72 four, 73 and more five — plain or under "at least"
  19.2 with 3.75 before alike; ours gave 54 four and 69-72 five. The
  picture still stands on the line's baseline with the descent under
  it where the pitches leave room. The lab now matches to 0.1pt.
  zh-9c5d0c3f 81.6% -> 90.8 (its pages 5 and 7 whole); Chinese sample
  97.09 -> 97.23; POI unchanged by it.

- **The legal Chinese numbers say 壹拾 (2026-10-15).** Counting forms
  write ten to nineteen without the leading one (十, 十一); the legal
  (financial) forms keep it: zh-64044a1d's tenth chapter heading is
  "壹拾、" in Word's print (`ideographLegalTraditional`), and ours read
  "拾、". The legal forms — Traditional and Simplified — now keep their
  壹. zh-64044a1d's page 69 whole; nothing else moved.

- **The East Asian line rules hold only for East Asian text
  (2026-10-15).** Word keeps a closing mark from starting a line, an
  opening one from ending it, and lets a mark hang past the margin,
  by the rules of the text's East Asian language — and an English one
  has none. Lab `kc` (Word 16, mode 14, SimSun 12): with the defaults'
  `w:eastAsia` en-US, "…abcdefgh" and "…測試測試測試" leave "，" and
  "）" to open the next line; under zh-CN they stay (the comma hung).
  zh-6600d539 tags most of its runs zh-TW over an en-US default, but
  not its "，針對平臺…": Word's print starts a line with that comma.
  The rules now go by each run's own `w:lang` East Asian language,
  else the document's (Chinese, Japanese or Korean keep them). Taken
  for the whole document it was wrong — seven documents of the same
  en-US default whose runs say zh-TW fell 1 to 5 points. zh-6600d539
  97.8% -> 100, zh-64044a1d 93.0 -> 95.6; Chinese sample 97.23 ->
  97.30; POI unchanged.

- **A line may end after "×" in East Asian layout (2026-10-15).** The
  multiplication sign sits in the Latin-1 letters' range, so the
  fitter read it as a letter of the word beside it and the engine kept
  it with the number after it; and the formula rule (bug59058's math
  runs) joins it to its neighbours. In a document of East Asian layout
  Word parts a line after it: zh-b56eeded's "…預算員額總數)×" ends a
  line before "100%" in Word's print, where ours carried "×" down. "×"
  and "÷" are no letters now, a line may part after "×" under East
  Asian layout, and the formula rule joins "×" outside it only.
  zh-04f73697 99.0% -> 100, zh-b56eeded 99.0 -> 100, zh-e061a08e 93.0
  -> 94.3; Chinese sample 97.30 -> 97.35; POI unchanged.

- **A list level begins at its own start (2026-10-15).** Numbers
  counted from one wherever a list began, the level's `w:start` taken
  only through a restart. zh-a7728bc9's fifth heading is a list of its
  own whose level starts at 5 — "五、" in Word's print, "一、" in ours —
  and zh-ac627439's "十二、附则" read "一、附则", its first line a
  character longer. A level not yet counted (or reset by a higher one)
  now begins at its start; a parent level not yet counted shows its
  start too. zh-ac627439 99.5% -> 99.7; nothing else moved by 0.3.
  (2026-10-29) And counts it so: a shallower level not yet counted when
  a deeper item comes first is counted at its start, and the next item
  there is the one after. zh-505b9619's list opens at level 2 ("1.1"),
  and Word for Windows numbers its first level-1 items 2 and 3; ours
  numbered them 1 and 2. Pair d645363c, 756 Windows mode: only
  zh-505b9619 96.6 -> 96.8 (v2 matcher 97.9 -> 98.1).

- **A flattened table's cells keep their room above and below
  (2026-10-15).** A nested table too big or too deep to be a block is
  flattened into its cell, and lost the top and bottom margins and cell
  spacing that stood round each of its cells. drawing.docx's article
  heads stand in HTML tables three deep (cell spacing 7 and 15 twips,
  margins of 75 and 15): its "12.04.2006 - Cbonds" line stood 11pt high
  of Word's print and the pages after it ran a line early. Each
  flattened cell's first paragraph now takes its top margin and the
  spacing above (twice in a first row), its last the bottom margin and
  spacing below; the kept markup saves the table as written. The line
  now stands 5pt high (a separator row of the outer table, 5.3pt in
  Word's print, is not yet ours). drawing 80.8% -> 81.7; 60329 2.1 -> 0
  (its two chance matches against Word's print of its text off the
  page); the Chinese sample unchanged.

- **A picture in a bordered run: its line holds the border (2026-10-15,
  Linux, from Word's print alone).** bug59058's tables are pictures
  ("tab1" 75 x 72.75pt, "tab2" 75 x 30), each alone in its paragraph,
  in a run with a character border (`w:bdr` single, sz 6, space 0,
  CCCCCC, `w:frame`); tab1 has `wp:effectExtent` b 9525 as well. In
  Word's print the picture lines are 75.0 and 31.56pt: the border's
  0.75 above, the picture, its 0.75 of effect, the border's 0.75 below
  — and the picture 0.75 in from the text's left, the grey lines drawn
  round picture and effect. Ours set the picture flush in a line of its
  own height and drew no border, so every line after tab1 stood 2.25pt
  high and after tab2 3.8pt — enough to miss the ±3pt match from p27.
  An inline picture now carries its run's border (`frame`) and its
  effect extent's top and bottom; its line, paragraph or in-line, is
  taller by both and the border is drawn, while the picture keeps its
  file's size (resized, it is written without them). p27 now within
  0.3pt of Word's; bug59058 73.9% -> 74.9% (Linux), its next parting
  p38; nothing else moved. Text runs with borders (zh-06c46ba9's 42)
  are untouched: not measured. Left: a picture paragraph's shading is
  drawn one text line tall, not the picture's line.

- **Times and Arial keep their line gap over the text (2026-10-15,
  Linux, from Word's print alone).** bug59058's references are 13pt
  Times at least 15pt, their journal titles in MinionPro (Cambria in
  Word, Caladea here). In Word's print a line with a title on it steps
  15.24 (15.12 and 15.36 on its 0.24pt raster), a Times-only line 15.0;
  ours 15.45 and 15.0, 2.3pt short by p38's foot. Word sets a face's
  whole line gap over its text (Times's baseline .891 + .042 down its
  1.15-em line: `face`'s 0.933); the engine shares it out half over
  and half under, whatever the leading distribution — Skia folds the
  gap into the face's own height before a style's `height` is
  applied, so `.proportional` changed nothing. A line of Times and
  Cambria (no gap) was then Cambria's ascent over Times's descent and
  half its gap. Writer now draws the Times and Arial stand-ins as
  `Liberation Serif Word` and `Liberation Sans Word`: the same faces
  with the hhea gap added to the ascender (`OfficeFonts._gapAbove`,
  in memory; `build/tools/font-gap-above.py` stages the browser
  build's copies — not built here). The mixed line is 15.2, the
  Times-only one 15.0 with its baseline 12.18 down (Word's 12.19, the
  engine's had been 11.90). bug59058 74.9% -> 89.1% and Word's 52
  pages (Linux). Nothing else moved but form_footnotes, 92.0 -> 90.8,
  whose lines all moved 0.1pt or less (toward Word's): a footnote
  mark now stands within the matcher's 2.5pt of the heading beside
  it and is read into its line. Slides and Sheets keep the plain
  faces. Carlito (Calibri's gap .22) is left as it is: Word's Calibri
  is not set by its hhea, and needs its own measure.

- **An empty `<w:pict/>` is nothing (2026-10-15, Linux).** bug59058's
  p45 table follows a paragraph whose one run holds an empty
  `<w:pict/>` (an HTML page's leftover). Word's print shows no mark
  and gives it no room; ours read it as an object of unknown size, a
  300 x 200 grey stand-in, and the table stood 187pt low. An empty
  `w:pict` or `w:drawing` is now skipped. bug59058 89.1% -> 91.7%;
  nothing else moved.

- **Lucida Sans Unicode keeps its own tall line (2026-10-15, Linux).**
  Word's print of bug59058 embeds the face: hhea ascender 2246,
  descender -901 of 2048, no gap — 1.537 ems, the baseline 1.097 down;
  its 9.5pt single lines step 14.52 on the 0.24 raster. Ours set it as
  the sans clone, 1.15 ems, so p48's fact-sheet heading and the table
  under it stood 1.4 to 5pt high. `face` now gives it that line and
  baseline (its widths, wider than Arial's — "o" .608, "n" .614 — are
  not taken: the print's subset holds 45 characters). The table now
  within 0.2pt; bug59058 91.7% -> 92.2%, the only document with the
  face.

- **Math letters are named on Linux (2026-10-15).** Cambria Math's
  formulas are runs of Mathematical Alphanumeric Symbols (𝑆 U+1D446,
  𝑧, 𝛼). Linux's font manager finds no face for a character by itself
  (as with Chinese, 03694462), so bug57031's formulas printed as
  missing-glyph boxes, and their lines read as nothing to the matcher
  though they stood where Word's do. The Linux glyph fallbacks now end
  with STIX Two Math, DejaVu Math TeX Gyre and Noto Sans Math (a serif
  first, as Cambria Math is); the widths stay Cambria Math's
  (`cambriaMathAdvances`). bug57031 87.0% -> 87.3%; nothing else moved.

- **Endnotes are set after the last paragraph (2026-10-15, Linux).**
  The endnotes part was kept for the save and never drawn. Each note
  is now read like a footnote (`RichDocument.endnotes`, its own mark —
  `w:endnoteRef` — in the endnotes' numbering, lowerRoman by default),
  and the layout sets them where Word's print does: under the body's
  last paragraph, the separator first — the footnotes' 144pt rule in
  its own paragraph — then the notes in the order of their marks.
  endnotes' rule stands at 427.2 to Word's 426.1, its note's baseline
  0.2pt from Word's. Bug54849 95.7% -> 100%; endnotes unchanged in
  score (its "i" mark stands 0.6pt lower than Word's and the matcher
  then reads mark and note as two rows — the raise of a superscript,
  0.3 of the full size here as in PowerPoint, is 0.36-0.37 in Word's
  print at 10 and 11pt: not changed). Not built: notes that do not fit
  on the last page (Word runs them on to pages of their own; ours sets
  none), and endnotes at a section's end (`w:pos` sectEnd).

- **A superscript stands higher in Word (2026-10-15, Linux).** Every
  note mark in Word's prints of the corpus (51, in endnotes, footnotes,
  table_footnote, Bug54849, bug65649 and form_footnotes; Calibri and
  Times alike) is raised 3.6pt over 10pt text and 4.08 over 11 and
  12pt: 0.355 of the full size within the 0.24pt raster. Ours took
  PowerPoint's 0.3 and stood them 0.6pt low. Under Word's rules the
  raise is now 0.355 (`_paintScripts`); bug65649's marks within 0.07pt,
  endnotes' within 0.26. Paint only: no line moves and no score.

- **A paragraph holding a note mark gets its baseline too (2026-10-15,
  Linux).** A raised or lowered run makes a paragraph's runs unequal,
  so it got no strut, and the baseline correction (`_inkShift`) was
  only made under a strut: the engine's even share of the 1.15
  multiple's extra stood endnotes' "A pendant worn…" (an "i" mark among
  11pt Calibri) 1.6pt under Word's, its height right. A paragraph whose
  lines are all one height and whose only odd runs are scripts now
  takes the same correction; that paragraph within 0.2pt. No score
  moved: endnotes stays 92.9%, its last miss the matcher reading our
  note's "i" as a row of its own (4pt over "XXX"'s box foot; Word's
  print writes the two as one text line).

- **A table floating over a footer's text takes no room (2026-10-16,
  Linux).** PageSpecificHeadFoot's second-page footer is a page-number
  table anchored to the text (`w:tblpPr` vertAnchor text, `w:tblpY` 1
  twip) and a line after it. Word's print sets the line where it would
  be with no table and lays the table over it from the line's top, its
  second row under the footer's bottom: "Page 2" 18pt under the line,
  where ours had laid the table in the flow above it. In a header or
  footer (`floatsFrames`) such a table now takes no room and stands its
  offset under the next paragraph's top (`_floatsOver`); the body keeps
  laying it in the flow, where a full-width one pushes the text below
  it anyway. PageSpecificHeadFoot 90% -> 100; the only corpus file with
  a floating table in a header or footer.

- **A metafile's text falls back to the documents' faces (2026-10-16,
  Linux).** tika-3388's attachment icon is an EMF whose caption,
  "約翰的測試文件", is set in MS Gothic; the player drew it in the Latin
  face standing in for MS Gothic and nothing else, so the caption was
  seven empty boxes (written to the PDF as NULs). A metafile's text now
  carries `RichTextTheme.glyphFallback`, as the body's does: seven
  full-width ideographs, 63pt to Word's 62.4. tika-3388 50% -> 100. The
  caption's baseline stands 2.7pt under Word's (the fallback face's
  ascent, not MS Gothic's): left.

- **An HTML block's margins space its paragraphs (2026-10-16, Linux).**
  A paragraph naming an HTML block (`w:divId`) is spaced by the block's
  `w:marTop` and `w:marBottom` in the web settings (twips): drawing.docx's
  one such paragraph, an empty cell under a banner, names a block of 15
  over and 75 under inside a body block (`w:bodyDiv`) of 150 all round,
  and Word's print stands the next article 4.5pt lower than ours did —
  the block's own margins, the body's nowhere. The reader keeps every
  block's (`RichDocument.divMargins`) and the layout adds a block's top
  over the first paragraph of a run naming it and its bottom under the
  last. drawing 82.5% -> 86.7 (page 15 exact); no other corpus file has
  a block with margins.

- **A cell's paragraphs share their spacing too (2026-10-16, Linux).**
  The space after a paragraph and the space before the next shared the
  room in the body only (b388f95c: "not yet inside a cell"). In a cell
  Word does the same: drawing.docx's "Ведомости и МАЗАЙ" and "Вкратце",
  headings of 12pt before and 3 after in an HTML table's cell, are 12pt
  apart in its print, and every line under them stood 3pt low; and
  zh-06c46ba9 p41's case box, "問題檢討的寫法" over the next paragraph,
  62.0 apart in Word's, 69.3 in ours, now 63.3. `_cellSharedSpace`
  takes the smaller of the two between paragraphs of one cell, as
  `_sharedSpace` does in the body (automatic spacing keeps its own rule
  in `_spacing`). drawing 86.7% -> 87.4, form_footnotes 90.8 -> 92.0,
  zh-15728c84 94.0 -> 96.0, zh-e27cd8bf 99.8 -> 100, zh-457a8d62 +0.1;
  zh-06c46ba9 80.9 -> 78.6 — it was already two lines behind Word from
  p41, and where its page 44 ends moved with the nearer spacing (a
  heading at the foot now takes its next paragraph's first two lines).

- **A floating frame of no width stands where it is aligned (2026-10-16,
  Linux).** Bug51170's footer page number is a frame (`w:framePr`)
  aligned right in the margins (`w:xAlign` right, `w:hAnchor` margin)
  with no `w:w`: Word sizes such a frame to its text and sets it at the
  right margin. Ours took the band's whole width for the frame, so the
  alignment had no room to move it and the number stood at the left
  margin on every page. Laid over the band, the frame's text is now set
  right (or centred) as the frame is. Bug51170 96.9% -> 100, zh-457a8d62
  98.7 -> 100; nothing else moved.

- **A stroke holds the letter after it, in any alphabet (2026-10-16,
  Linux).** Word parts Latin text at spaces and after hyphens alone, and
  the engine's break after "/", "?", "!", "|" and closing brackets was
  held by a word joiner only before an ASCII character. bug65649's
  "ИО102-20/А2М" parts after the hyphen in Word's print; ours parted
  after the stroke and carried "А2М" down alone. The joiner now goes in
  before any letter or digit that is not East Asian. bug65649 99.7% ->
  99.8, form_footnotes 92.0 -> 97.7 (Word's three pages, where ours had
  two); nothing else moved.

- **A larger list number raises its line and sets it no deeper
  (2026-10-16, Linux).** b879226a gave a number larger than its text
  (its level's `w:sz`) a whole line of its size, through a zero-width
  space in the box before the text. Word's print gives it the height
  above the baseline only: bug65649's "3.1.1." paragraphs, a 14pt number
  over 12pt Times, stand 15.72pt under the line above and their second
  line 13.8 under the first, as under any line of the text; ours were
  15.65 and 14.25, and each numbered paragraph set what followed 0.45pt
  lower — 3.2pt by the foot of page 122. The box now holds a placeholder
  as tall as the number's line above its baseline and reaching no lower
  (and the paragraph takes no strut, which would undo it). Not on a line
  grid, where lines are set by pitches: zh-64044a1d's "圖1" captions, a
  12pt number over 11pt text, stood 6pt low that way, and keep the whole
  line. bug65649 p122 within 0.2pt (was 3.2); its score 99.8 either way,
  one line more matched; nothing else moved.

- **A list number's tab reaches the paragraph's own stops (2026-10-16,
  Linux).** With no hanging indent the number's tab went to the
  paragraph's own stops only when they stood before the indent, and
  otherwise to the next default stop. Word takes the paragraph's next
  stop past the number however far: bug65649's "3.2.1.3." (a first-line
  indent of 567 twips, the number ending at 67.6pt, stops at 284, 709,
  1134 and 1843) starts its text at the 1843 stop, 177.1pt on Word's
  page; ours set it at the default stop, 155.9, and the line took a word
  more. A bar stop is no stop here. bug65649 99.8% -> 99.9 (six lines);
  nothing else moved. The hanging case is as it was, the cell case of
  1cebd4fa included.

- **A body word wider than the line opens a line of its own (2026-10-16,
  Linux).** c488db0d took such a word to a new line in cells under 150pt
  only. Word does the same in the body: bug65649's "Замечания: " and
  142 underscores is the label alone and two lines of underscores in its
  print; ours parted the underscores straight after the label, and the
  form ran a line short. In the body of a document of no East Asian
  layout a word of twenty characters or more, after a space, that is
  wider than the line now opens one (East Asian documents keep parting
  such a word where it stands, as 8788bcef found). bug65649 99.9%, one
  line more matched; nothing else moved.

- **Lucida Sans Unicode at its own widths (2026-10-16, Linux).** Its
  stand-in is the sans clone at Arial's widths, and Lucida's lower case
  is 5-37% wider (its digits all 0.632, its space 0.316, its hyphen
  0.579): bug59058's "SEER 9 Incidence 1975-2011 & U.S. Mortality…"
  note is two lines in Word's print and was one in ours, and its last
  four pages stood a line off. Word's print embeds the face's subset
  with /Widths for the 41 characters the document sets in it, all of
  them; those are the face's advances now, and the other ASCII are
  estimates from Arial's (capitals 0.96 of them, lower case 1.12, other
  signs 1.14). bug59058 92.2% -> 100. In the same build WordWithAttachments
  went 2.6 -> 5.3 and zh-64044a1d 95.6 -> 95.7; neither names Lucida, and
  another session's commit was in that build too — not traced.

- **A group's text boxes apart from each other keep their own places
  (2026-10-16, Linux).** cabe6fad read a group's text boxes whole when
  they stand one above another at one width; any other group kept its
  first box's text alone, set at the group's left. shapes-with-text's
  group is an arrow with "A group of shapes" in it and a text box under
  it at another place and width (two stars beside them, empty): the
  arrow's text stood 85pt left of Word's and the box's was never read.
  Now each box's paragraphs take its column in the group — its shape's
  left and width, the preset's text rectangle (the arrow's) and its
  insets — as indents, and a part of the group's box from its own top;
  the group's box has no insets of its own. The parts' placing (the
  layout's) is measured at the text now, again until it stands: the
  space before a part's first paragraph was shared with the paragraph
  above's space after, another box's, and the text box stood 8pt high.
  shapes-with-text 62.5% -> 100, zh-06c46ba9 +0.2; 60316 as it was.
  Boxes side by side whose texts overlap in height still stack.

- **A line holding a picture alone is as tall as its text (2026-10-16,
  Linux).** drawing.docx's article mastheads end in a cell of tiny
  pictures between line breaks in 8.5pt Arial ("0.8x1.5pt, br,
  161x12.8, br, 0.8x2.2"): Word's band is 32pt, each line a line of
  that text at least; the engine's line holding a placeholder alone is
  the placeholder's height, and ours was 17pt — every masthead 5pt
  short and the article under it high. A picture in the text that stands
  alone between breaks (or the paragraph's ends) and is narrower than
  the line, and shorter than a line of its text, now has a zero-width
  space before it in the style of the break beside it (the picture's
  run keeps no look of its own: the masthead's breaks are 8.5pt Arial,
  the paragraph 12pt Times, and in the paragraph's style the band came
  out 43pt). A taller picture's line is its own height, with no depth
  of the text under it: the 12.8pt banner between two breaks is a line
  of 12.7 in Word's print. The band is now 33.6 and the dark one under
  it 55.5 (Word's 32.2 and 55.0). Only alone: before every inline
  picture, chartex's chart (as wide as its column, a space after it)
  went to the next line after the space, and zh-9c5d0c3f's road signs
  in cells moved 6-8pt. drawing 87.4% -> 89.7; nothing else moved. Its
  page 9 still stands 20pt low: the masthead starts that much under
  Word's, from the empty paragraphs above it (not looked into).

- **A cell that states no margins has its table's — or its row's
  (2026-10-15).** Where most of a table's cells state their margins
  (`w:tcMar`, as HTML converters write them), the table's margins were
  taken from the cells, and a cell stating none got those. Word gives
  such a cell the table's own margins, or its row's where the row has
  an exception (`w:tblPrEx/w:tblCellMar`). drawing.docx's article table
  says 105 twips above and below; its rows zero them cell by cell, its
  logo row by its exception, and its article row not at all — Word
  sets the article 5.25pt down, ours set it flush, and with the
  flattened tables' room above it stood 5pt high. drawing's page 8
  whole: 81.7% -> 82.5; nothing else moved.

- **Before 2013's layout the next character is taken half the one
  before it over (2026-10-15).** The legacy rule took a character where
  it was half its own em or less over the line, the line's marks giving
  it. It is half of the character BEFORE it, as set: lab `lq` (Word for
  Windows, mode 12, 宋体 and Arial 10.5, justified, a "；" on the line to
  give, in ~/starling-doc-check/lab/lq) takes the next ideograph up to
  5.2pt over after an ideograph, but after "-" or ")" 1.75 and not 2.0,
  after "." or "/" 1.25 and not 1.5, after "i" 1.0 and not 1.5, "m" 4.0
  and not 4.5, "W" 4.5 and not 5.0 — and a "W" after an ideograph 5.0
  over, past its own half. An automatic space between the two goes with
  the Latin side: "…丙3.0" then "米" is taken 4.0 over and not 4.25,
  half of "0" and its 2.63 of space ("-3.0-" then "米", 1.75), while
  zh-9dd9ce6d's "…次年" leaves "3" 9.75px over, space and digit
  together over half of "年" alone. zh-1a3c7aa0's cell line "…苯；2,4-"
  now leaves "二" (4.6 over) for the next line as Word does, and so
  does the Mac's open zh-1563bd74 line: "…自救能力”" leaves "的" 3.95
  over a Times quote whose half is 3.55 — every variant of lab `sq15`
  falls on the same rule. Chinese sample 97.86% -> 97.89
  (zh-e27cd8bf +0.8, zh-1563bd74 +0.5, zh-d68ac84a +0.4, zh-e37f8d40
  +0.3, zh-1a3c7aa0 +0.2); POI unchanged; nothing down.

- **A row that goes over whole holds the merged cell's text it takes
  with it (2026-10-15).** zh-e6d54ae4's "依據服務特性…" is merged down
  over three rows; the third ("3.旅服中心每半年…") has no line at page
  5's foot and goes to page 6 whole, and the merged cell's last five
  lines go with it. Laid out again at the page's head, the row stood at
  its own height — the merged text had been taken up again there, but
  only a row that had already parted counted it — so the line that had
  stood across page 5's foot in the flow, gone over whole, pushed
  "施。" half a line under the row and the next row's text 16pt above
  Word's. Such a row is now as tall as the merged text asks too, its
  rules drawn to there. zh-e6d54ae4 93.5% -> 99.2; nothing else moved.

- **YaHei's ellipsis is its own width (2026-10-16).** zh-457a8d62
  quotes its statutes with "……" in 標楷體 runs hinted East Asian; Word
  on a Mac sets them in Microsoft YaHei, 13.52pt apiece at 16pt on the
  document's grid of 1.0076 — YaHei's own 0.8135 em (13.016) and half
  the grid's addition, as any half-width character takes it under
  balanced widths (lab `cg3`). Ours drew the stand-in's em-wide glyph
  with the whole addition, 17.01, and its lines "…奢侈放蕩……等，足以
  損失", "…罰金：……三、" ran a character short. The East Asian YaHei
  face now carries the width (0.9629 in bold), and a symbol so set
  takes it and half the grid's addition. zh-457a8d62 95.1% -> 97.2,
  zh-e37f8d40 96.7 -> 100; POI unchanged.

- **Taiwan's centred marks do not close up before a closing bracket
  (2026-10-16).** Where punctuation is kerned, the first of two marks
  standing together gives half an em. Lab `cu` (Word 16, mode 15, 16pt
  新細明體 under zh-TW, 宋体 under zh-CN, in ~/starling-doc-check/lab/cu):
  under zh-TW "。」" and "。）" stay a full em apart, while "：「", "，「",
  "、「", "）」", "」」", "」。", "」，" and "）。" close up by half — a
  centred mark has no blank half on the side of a closing bracket, which
  has none there either; under zh-CN every pair closes up.
  zh-457a8d62's line opening "產。」" set the "。" half an em narrow and
  took a character Word wraps. zh-457a8d62 97.2% -> 98.6; nothing else
  moved.

- **A row opened by a paragraph kept with the next neither parts nor
  leaves what follows its table (2026-10-16).** Labs `kr` and `kn` (Word
  16, modes 14, 15 and legacy, in ~/starling-doc-check/lab/kr): a
  one-row table of twelve paragraphs with room for eight at a page's
  foot goes to the next page whole where its first paragraph (the first
  cell's) says `w:keepNext`, and parts where a middle or last one does,
  or the second cell's first; and a four-paragraph row that fits the
  foot, with no room for the paragraph after the table, goes over with
  it. form_footnotes' "INSTRUCTIONS" box opens with a Heading 5 and fits
  page 2's foot by 5pt, but not with the document's last mark under it:
  Word prints it on page 3. Not where the paragraph after opens a page
  of its own (zh-9e08ed28's row "3、推廣…" stays at page 15's foot, the
  heading after it led by a page break), and not with the table's next
  row — unmeasured, and zh-64044a1d's equipment list, every row kept
  with the next, Word parts between "8" and "9". form_footnotes 92.0% ->
  97.7, Word's three pages; nothing else moved.

- **A merged cell is centred in the rows that fit the page with their
  rules (2026-10-16).** A centred cell merged down over rows that go
  over a page is set in the rows on its page (2026-10-14, above). Those
  rows were counted while each fitted without the line under it, as the
  rows themselves are not set: zh-90e0cea8's "行政审批各阶段帮办服务内容",
  merged over 30 rows, was centred over 13 on page 8 where the 13th,
  16.1pt with 0.3 left, goes over with its line — half a row, 8.6pt,
  under Word's. zh-90e0cea8 93.8% -> 96.6 (T31); nothing else moved by
  it.

- **A merged cell's rows on the page take in the part of one that
  parts there, and a row of no cells of its own (2026-10-16).** Two more
  for the rows a centred merged cell is set in on a page (above). A row
  every cell of which is merged down from above has no height of its own
  and stopped the count: zh-84702a67's "是否存在转包、挂靠行为", merged
  over twelve rows from the head of page 8, was centred over five of
  them, 95pt high of Word's; it is now 5pt low. And a row of the span
  that parts at the page's foot gives what it keeps there — to its last
  line on the page and its margin, where every cell of it keeps one —
  unless it is the span's last row: zh-6cd1befe's "事故灾难类" ends with
  "辐射事故", which parts at page 48's foot, and Word centres it in the
  rows above that one; zh-91e44bcb's "（五）不予处理" also ends with the
  row that parts ("5.要求行政机关确认…") and Word centres it down to
  that row's first line, 5pt from ours. The difference between the two
  is not known (T31). zh-abe7e063 98.4% -> 100, zh-64044a1d 95.6 ->
  96.0; nothing else moved.

- **The span's last row counts its part too, unless its stated height
  has no room (2026-10-16).** The rule above left out the span's last
  row when it parts, for zh-6cd1befe's "事故灾难类"; the reason is
  another: that row, "重污染天气事件", says at least 43.65pt with 33 left
  on page 48, and such a row is not begun there but goes over whole
  (`splitRow`), in Word's print as in ours — so it gives the cell
  nothing on the page. zh-91e44bcb's "（五）不予处理" ends with a row that
  does part ("5.要求行政机关确认…", its first line on page 4), and Word
  centres the cell down to that line. zh-91e44bcb 96.4% -> 97.1; nothing
  else moved (T31).

- **A parting row gives a centred cell's own height to the part, not
  where the row's middle put it (2026-10-16).** What a row that parts
  at the page's foot keeps there was measured to each cell's last line
  as the flow set it; a centred cell whose text fits the part is set in
  the part (`splitRow`), and gives it only its own height. zh-84702a67's
  row "10" has a top-set cell of two lines at the foot of page 8 beside
  the number and two blank cells, all centred, whose one line the flow
  set in the middle of the 76pt row: the part came out 9.5pt deeper
  than Word's, and the merged "是否存在转包、挂靠行为" stood 5pt low; it
  is now where Word has it. zh-84702a67 98.2% -> 100; nothing else
  moved (T31).

- **A parted row's part ends where Word closes it (2026-10-16).** The
  part of a row parted at a page's foot was ruled down to the foot, and
  the merged cells centred beside it counted it as only its kept line
  and margin. Word closes the part at its own height, no less than the
  row's stated one: zh-91e44bcb's "5.要求行政机关确认…", at least 38.95pt,
  keeps one 31.2pt line on page 4 and Word draws its bottom line 40.1
  under its top, 16pt above the foot; its "三、本年度办理结果" and
  "（五）不予处理" stand centred over that part (ours 3.5 to 5pt high,
  centred on the line). Not where a cell merged down from above runs
  its text on below the part (zh-e6d54ae4's "(二)衡酌實際需求…" beside
  a parted row): the part is then to the foot, as before. (T32.)
  zh-91e44bcb 97.1% -> 100; nothing else moved.

- **A face Word emboldens widens a character by 1/48 of its size
  (2026-10-17).** Word sets bold in a Chinese face it has no bold of
  (仿宋, the stand-ins) by widening each character; ours by 1/57 em,
  0.28pt at 16pt. zh-15428325's bold "（一）使用房票基础奖。" and "（二）税收
  优惠政策。" lines (16pt spaced -0.3 under `w:balanceSingleByteDoubleByteWidth`)
  took "励" and "类" 7.49 and 7.48pt over in ours — inside half their
  spaced advance, 7.7 — where Word sends both down: with ten bold
  characters each (and Word's first line 0.15 further in), Word's bold
  is at least 0.315pt a character, 1/50.8 em (the Mac session read
  0.31 off a justified line, T66). 1/52 took the first line, 1/48
  (0.33) both. zh-15428325 94.8% -> 98.7 (pages 2, 5, 6); nothing else
  moved, in either set. (Word for Windows emboldens less — lab `bold`,
  the same line: about 0.1pt a character — so a Windows lab cannot
  measure it.)

- **A paragraph in no list takes no indent from its style (2026-10-17).**
  A paragraph whose `w:numPr` says `w:numId` 0 (in no list) takes no left,
  hanging or first-line indent from its style, in twips or characters;
  what its own `w:ind` says stands. Lab `lc`/`lc2` (Word for Windows,
  zh-15428325's package, its style "table of figures" at leftChars 200
  and hangingChars 200, the paragraph naming firstLineChars 200): with
  `numId` 0 the lines are at the margin and the first two characters in;
  without the `w:numPr` they keep the style's two characters (97.6 and
  129.6 against 76.6 and 108.6). zh-15428325's paragraphs carry the
  `numId` 0. 2f4793e4 (the Linux box) reaches the same lines of
  zh-15428325 by taking the hang out of the inherited left whenever a
  first-line count replaces it — which the lab without `w:numPr` says
  Word does not; on top of it this moves nothing in the sweeps.

- **A justified line's automatic spaces give without word spaces too, a
  quarter of an em in all (2026-10-17).** b9952df9 let the automatic
  spaces between ideographs and Latin give with a line's word spaces,
  half of themselves at most. A line with none of the latter gave
  nothing: zh-c5f59397's "期程自112年度至114年度，113年度…貨櫃" (mode 15,
  justified, no word space — the gaps Word's PDF shows as spaces are
  its automatic ones) takes "櫃" 1.16pt over, its five set at 2.7 of
  3.0. They now give there too, half of each and a quarter of an em on
  the line at most: zh-adfe24a7's "…善用GIS、…計畫執行" leaves "行"
  2.88pt over with one (half of it is 1.5), and zh-c5f59397's "…3艘35噸級
  巡緝艇及3艘5噸級快艇，113年度預定辦" takes no "理" with eight (whose
  halves alone would take two characters). zh-c5f59397 98.5% -> 100;
  nothing else moved. (Uncapped, zh-3c055c9b went 44.9 -> 70.1 and
  zh-c5f59397 to 89.9: a lead for zh-3c055c9b's lines.)

- **Times and Arial keep their line gap over the text on Windows too
  (2026-10-17).** Writer draws Liberation Serif and Sans as Word holds
  Times and Arial, their `hhea` line gap moved over the ascent (T19).
  The engine on Windows reads a face's ascent through DirectWrite, from
  `OS/2` `usWinAscent`, and takes the gap as what `hhea` says beyond the
  Windows ascent and descent — so the change moved nothing there, and a
  line with Times beside Cambria stepped 15.45 where Word's steps 15.24:
  bug59058's references drifted 2-4pt a page and parted a line early
  from page 38 (75.2% here, 100 on Linux). `usWinAscent` is now raised
  by the same gap (FreeType and CoreText read `hhea`, as before), and a
  load that fails says so. bug59058 75.2% -> 100, zh-8112041b 70.8 ->
  100, zh-c5b5087b 83.7 -> 85.2, delins 73.3 -> 75.0 on the Windows box;
  form_footnotes 98.9 -> 97.7, the matcher joining a footnote mark to its
  line as it does on Linux.

- **A justified line's automatic spaces give with its word spaces
  (2026-10-16).** From Word 2013's layout on a justified line's spaces
  give a quarter of themselves for what is over; the automatic spaces
  between ideographs and Latin gave nothing where punctuation is not
  compressed. zh-b13d0fb4 (mode 15, `doNotCompress`) sets "家新創品牌
  Startup Island TAIWAN，提升臺灣國際能見度。" on one line of a 304.6pt
  cell, 2.46pt over: Word's print has its two spaces at 2.3 of PMingLiU's
  3.12 and the space after "牌" at 1.8 of 3.0. Ours gave the spaces'
  1.4 and left "度。" a line of its own. The automatic spaces now give
  up to half of themselves there too (the most they give from 2013's
  layout on where marks are squeezed), every space the same share of
  what it can. zh-b13d0fb4 93.5% -> 100; nothing else moved.

- **A centred cell merged down parts from its text's start
  (2026-10-16).** A row that parts at a page's foot under other text
  takes the lines of a centred cell too tall for the room from where its
  text starts, not from where centring puts them — but only for a cell
  of its own row. zh-4d143b5e's row 11 (at least 66pt, its first three
  cells centred and merged down over six rows, 414pt) starts at 626 of
  698pt on page 6: centred over the six rows, those cells' first lines
  stood below the foot, no line of them fitted, and the row went over
  whole — every page after it 50 to 120pt behind Word's. Word parts the
  row with two lines of every cell on page 6, from the row's top. A
  merged cell now takes the same rule. zh-4d143b5e 36.5% -> 99.8;
  nothing else moved (T32).

- **YaHei's middle dot is its own width (2026-10-16).** Under Word on a
  Mac, Chinese names it has no face for (仿宋_GB2312, 方正…) are YaHei;
  our YaHei stand-in sets ASCII at YaHei's widths and left "·" (U+00B7)
  to Liberation Sans, Arial's 0.333 em. Word's print draws it in YaHei,
  0.2407 em (0.4395 bold, by msyh.ttc/msyhbd.ttc), in a hinted run and
  not. zh-6d1afa56's "·申报内容（含项目名称、项" fills its cell's 106.2pt
  in Word's print, the dot 2.2pt and the bracket and comma 2pt short
  each; ours put "项" on the next line, and its rows on p59 and p62 went
  down a line. zh-6d1afa56 97.9% -> 98.6; nothing else moved.
  Tried and dropped: all of YaHei's widths past ASCII (Latin-1, general
  punctuation, arrows, operators, shapes — "√" 0.7017, "■" 0.604, "─"
  0.7085 in this very print): 13 documents worse, zh-e5709b89 100 -> 36
  with its lines a character short from page 1 — so not all of them are
  Word's; settle them one by one.
  Then (same day) its "√", "─" and "■" in the East Asian face, at
  0.7017, 0.7085 and 0.604 em as this print has them (the box was an em
  under the symbols rule, the tick Liberation Sans's 0.549): zh-6d1afa56
  98.6 -> 99.0 (p34's ticked cells wrap as Word's); nothing else moved.

- **A frame that names a height and no anchor is set from the margin
  (2026-10-16).** A framed paragraph's `w:y` with no `w:vAnchor` was read
  as anchored to its text; the schema's default is the margin, which
  9c6cc3ca now places. zh-90e0cea8's cover ends with "山东省市场监督管理局
  发布", its frame at y 15027 twips under a margin of 16.9pt
  (`w:top="-338"`): Word prints it 784.9pt down the page, at the foot;
  from the page it would stand 13pt high, from the margin it stands 4pt
  under Word's (its exact 29.2pt line). The cover's score is as it was
  (5 of 10 lines: "ICS"/"CCS" 7.6pt high in their page frame, "37"
  33pt low — next); nothing else moved.

- **A cell's own right side is drawn where its neighbour draws no left
  (2026-10-16).** A table's inside lines between columns came from each
  cell's left side; a cell stating only its right (and bottom), beside
  one stating `nil` on its left, left no line between them. Word draws
  a side either cell states: zh-91e44bcb's tables, every cell right and
  bottom, printed as ruled rows without a column line. Under Word's
  rules the right side is drawn where the cell beside it draws no left
  (never both, which would double the line). Nothing moved in the
  sweeps (lines only).

- **No header repeated where a page breaks inside it (2026-10-16).**
  A table's header rows (`w:tblHeader`) were set again at the top of
  every page it went on to, even where the page broke between them.
  bug57031's "Test of Equality over Strata" has two header rows, its
  title and its column heads, and only the first fits under page 12's
  last table: Word opens page 13 with the column heads once, as rows
  going on, and repeats nothing — ours set both again above them, the
  heads twice, and its SAS code ran to page 14. Under Word's rules a
  page opened by one of the header rows repeats none of them.
  bug57031 94.4% -> 100; nothing else moved.

- **A box-and-whisker chart is drawn (2026-10-16).** Word 2016's
  charts live in a chartex part (`cx:chartSpace`), which nothing read:
  Writer showed the Fallback picture, the right look and none of its
  text. A chart whose series are all laid out "boxWhisker" now reads
  (`ChartXML.readBoxWhisker`) as its samples grouped by category on a
  column chart's axes, in a 2013-style chart's text (14pt title, 9pt
  grey labels), and draws (`ChartPainter._boxes`) as Word's print of
  chartex's: Excel's exclusive quartiles (QUARTILE.EXC; inclusive where
  the file says), the median across the box, whiskers to the furthest
  samples within 1.5 box heights, capped 6pt wide, the mean a 6pt
  cross, outliers 3pt dots; the outline the colour at 0.8; a
  category's boxes take its slot over 1 + `gapWidth`, 1.12 of a box
  apart. Word sets a chartex chart closer to its frame than a `c:` one
  — its title 2.2pt higher, its plot 2pt nearer the title and its foot
  4.4pt nearer the frame — and those are kept for one read from such a
  part. The axis's span covers every sample, so the scale is Word's,
  -100 to 150 by 50. Other chartex kinds (sunburst, funnel, …) keep
  their pictures. chartex's `c:chart` (in a chartex `a:graphicData`)
  names the part as well as `cx:chart` would. chartex 65.3% -> 76.4 (its
  page 2: 13 of 21 lines to 21); nothing else moved.

- **A row with rows merged down under it parts only where one of them
  begins (2026-10-23).** zh-9ef811c8's "监督检查" row (15.6pt at least)
  has every cell merged down over the three rows under it (15.6, 53.1,
  81), which hold nothing of their own. We draw those rows as part of
  the first, its "ghosts". Lab `mg` on Word for Windows (the document,
  its table moved 0, 3, 6 and 10 lines down): Word parts the group only
  at a row's top. The text fills the rows that fit and the next row
  goes over whole. Unshifted, it parts at the 81pt row's top, 84.3pt
  down (482.5 on p4), its channel list five lines on the page; three
  lines lower, after the second row (499.1). Ours parted the 81pt row
  wherever a line fitted, six lines down, and centred what then fit.
  `_CellGeo.ghostBounds` now keeps where each ghost row begins, and the
  part's room ends at the last one that fits; rows with lines of their
  own part as before. Ours parts at 479.8 and 499.2. zh-9ef811c8 27.0
  -> 37.9; the other 15 documents with such rows are unchanged. Left
  there: the label "综合业务", merged from the row above down into the
  group, Word centres in its part on the page (240-482), ours in its
  own first row.
  Then (the same day): such a part is as tall as the rows that fit,
  whatever its cells keep, and a cell merged only over the row's ghosts
  whose text fits that part is set whole in it, centred, as Word sets
  zh-9ef811c8's "●社会救助信访通讯地址…" (five lines; 402.8/449.6, Word
  403.7/450.5, the part's foot 481.7 to Word's 482.5). Ours had parted
  it where centring over all four rows put it, two lines on the page.
  Set whole without the part's height, the part shrank to its cells
  (474.9) and the document fell 37.9 -> 34.7. With it: 37.9 -> 39.3;
  the other 15 documents are unchanged.
  Then: the part that goes over is no shorter than the ghost rows that
  went with it. Lab `mg` has the 81pt row stand whole at page 5's head,
  and the next table's head under it. Ours carried only the three lines
  left of its cells, so everything after it stood 34pt high. Page 5's
  last line is now at 435.0 (Word 437.0; it was 400.8). zh-9ef811c8
  39.3 -> 50.2 (pair ghost-base4/ghost-new4); the other 15 are unchanged.
  Then, lab `gs` (Word for Windows; the document with its table shifted
  1-9 lines down, as in `mg`): where the merged text stretches the last
  of those rows, the rows' own stated heights are one more place to
  part. The "审批" row and the three under it (15.6, 15.6, 53.1, 48.95;
  133.25 in all) fit at those heights above page 6's foot (about 507),
  but its ten-line policy cell (about 160) does not. Word sets the rows
  at their stated heights with eight lines on the page and sends the
  two that stretch them over. It parts neither at the last row's top
  (84.3, ours) nor at the foot. The "办事指南" group (15.6×3 + 84 =
  130.8) does not fit at its stated heights, and parts at its last row
  top that fits, in every shift. Ours parted the "审批" group at 84.3,
  then the document ran to 11 pages. `ghostBounds` gains that bound.
  zh-9ef811c8 51.6 -> 62.1, 10 pages as Word's, pages 1-6 matched (pair
  gs-base/gs-new); the other 15 are unchanged. Simply parting a
  stretched last row at a line instead cost page 5 (51.6 -> 40.7).
  And what goes over there is the last row again, as tall as the file
  says it is (the rule for any row that goes over). Word's page 7 sets
  the two carried lines in the 48.95pt row, and the next row stands
  17.7pt lower than under ours, which made that part only as tall as
  its two lines. zh-9ef811c8 62.1 -> 99.3 (pair go-base/go-new); the
  other 15 are unchanged.

- **PMingLiU's en dash is an em (2026-10-22).** zh-05699f05's cells
  are 新細明體 throughout (its Normal names it for every script), and Word
  sets "（100%+目標值）–基準維護件數】"'s "–" 12.0 wide at 12pt. Lab `ds`
  on Word for Windows: the same beside ideographs, spaces, Latin letters
  or digits, hinted or not, under zh-TW or en-US. Ours drew the Latin
  stand-in's 6.67, and the cell's line held the "數】" Word sends down,
  then every row after. PMingLiU's East Asian face now gives U+2013 an
  em (`otherAdvances`). On Windows the face's fallback draws that glyph,
  and a fallback glyph's own spacing came out only before a space, so
  the dash's spacing now goes on a word joiner after it, as a no-break
  space's does. Its "×" is half an em (6.0) in Word's print, but set
  alone it let zh-e061a08e's "數）×100％" take "（以" back. The no-break
  space beside it is 6.0 in Word and 2.82 in ours, and the old 7.01
  "×" had hidden that, so both are left. Of 144 documents with
  PMingLiU and a dash or "×": zh-05699f05 79.4 -> 100, none down.

- **Marks in vertical cells are their vertical forms (2026-10-22).**
  Word's prints of tbRlV cells hold "︑", "︐", "︵" and "︶" where the
  files have "、", "，", "（" and "）": zh-b0401810, zh-cec9d337,
  zh-e49d7943, zh-65e6c317 and zh-74b34f3b. None of these files
  contains a vertical form itself. `_paintUpright` now draws each mark
  by Unicode's table (U+FE10 to U+FE44). Word sets the form off its
  square, with its ink about the middle of the character's place. In
  Microsoft YaHei: "︑" +0.56em down, "︐" +0.52, "︵" -0.19 (up), "︶"
  +0.19 (`_verticalFormDrop`; other forms not measured). zh-cec9d337's
  "︵" and "︐" now stand where Word's do. Its "︶" ends the line, in a
  box we narrow, and stands 2.7pt above Word's. Of the 22 documents with
  marks in vertical cells, zh-65e6c317 went 83.2 -> 84.2 and none moved
  down.
- **A letter-spaced vertical run: the spacing follows each glyph
  (2026-10-22).** Lab `vs` on Word for Windows (SimSun 10.5pt down tbRlV
  cells, spacing 0, 51 and 102 twips, left, centre and right) shows
  Word's rule:
  - Each character's place is its em plus twice the spacing (15.6pt at
    51 twips), and the glyph starts the place.
  - The whole run, trailing spacing included, is what the alignment
    sets. So a centred run's glyphs stand one spacing above the middle,
    and a right-set one ends two spacings short of the cell's end.
  `_paintUpright` centred each glyph in its place instead. It now sets
  the glyph at the place's start (laid out without the run's spacing).
  In the lab, the centred and right-set runs' ink now matches Word's to
  0.3pt (they were 2.3 late).
  - zh-b0401810's "职业资格证书…" (jc center, 51 twips) stood 2.55pt low;
    the score went 93.3 -> 97.4.
  - zh-e9616b2b went 97.2 -> 97.8.
  - zh-f2835e26 went 76.4 -> 75.8, but its ink is Word's: p6's column
    starts at 287.8 (Word 288.0, before 289.5), p7's at 218.0 (218.5,
    before 219.8). The line scorer reads a glyph's box from its font's
    ascender, and our SimSun stand-in's box stands about 2.2pt above
    Word's for the same ink (the lab's unspaced columns: ink equal, boxes
    2.2 to 2.5 apart).
  Left: a left-set spaced run with no indent still starts about one
  spacing late in the lab (ink 3.0pt late at 51 twips, 5.5 at 102).
- **Across a cell of text reading down, no margin on the left
  (2026-10-22).** Labs `vs/v2` and `v3` on Word for Windows (tbRlV cells
  62.5pt wide, 5.4pt side margins, set top, centre and bottom):
  - The lines run from the cell's right margin to its very left edge.
    Set at the bottom, the ink stands 1.6pt off the left rule, whatever
    the left margin (18pt in v3) or the bottom one (10).
  - Set at the top, the ink stands the right margin in (19.4 at 18pt).
  - Centred, it stands half the right margin left of the middle.
  - The top and bottom margins move nothing along the column either.
  Ours took both side margins off the room, so centred and bottom-set
  text stood 2.7 and 5.4pt right of Word's. Now all six v2 cases match
  Word to 0.5pt, and zh-b0401810's column is at x 101.9 (Word 101.3,
  before 104.6). Text reading up is not measured and keeps both
  margins. No line score moves among the 28 documents with such cells
  (the matcher does not weigh x).

- **Text in a table cell goes under a picture that leaves it no room
  (2026-10-22).** `_floatPush` set a body paragraph's text under a
  wrapped float of its own that left its first line less than an em on
  either side, but never a cell's. zh-e4ef4c4d p5 holds four photos
  anchored in cells (wrapTight, layoutInCell). The 184pt one, 15.4pt
  down in a cell 201pt across inside its margins, leaves no room, and
  Word sets its paragraph's six lines under it; ours ran them over it.
  Lab `wc` on Word for Windows (zh-e4ef4c4d's own package):
  - Lines of an exact height go down in whole lines from the
    paragraph's top until they clear the picture: 24pt lines to 168pt
    under a photo ending 153.75 down, to 144 under one ending 135.4 (or
    123, when anchored 3pt down).
  - A line of auto spacing goes to just under the picture (134.5 under
    one ending 135.4; its wrap polygon stops 1.6pt short).
  - The picture stays where the paragraph first started.
  The cell's text now measures the room across the cell's text, from
  the float's own x. zh-e4ef4c4d 93.3 -> 100. It is the only document
  in the corpus with a wrapping anchor in a cell, headers and footers
  included.
- **A wrapped picture stands no higher than its cell's top
  (2026-10-22).** A picture that text wraps round (square, tight,
  through) is placed from a paragraph in a table cell. Word draws it at
  the cell's top when its offset would put it above. zh-e4ef4c4d p5's
  photos, 179.7 and 191.7pt above their paragraphs eight lines down,
  stand at the row's 124.6 (ours 113.2 and 101.2), and its p4 pair
  likewise (413.9; ours 386.2 and 390.0). drawing.docx p9's square-
  wrapped icon is at 281.0 (Word 278.8; ours 219.6). A picture in front
  of the text or behind it is not held: zh-e49d7943's "附件5" box,
  wrapNone, stands 27.8pt over its table's first row in Word's print,
  and held to the row it cost a line (82.4 -> 82.2). Every anchor in a
  cell in the corpus says `layoutInCell="1"`, so it is not read. Only
  five documents anchor a picture in a cell above its paragraph; no line
  score moves. Nor further left than the cell's edge: drawing's icon,
  85.05pt left of its column, now stands at the cell's 85.1 (Word 86.6,
  the cell and its 1.5pt left effect, which the reader does not keep for
  an anchored picture; ours had it at the page's edge, x 0). Word's
  text then wraps beside it (91.9); ours runs under it.

- **An autofit cell grows to its picture, and to a table nested in it
  (2026-10-22).** `_minContent` counted text only, so an inline picture
  alone in its paragraph, and a nested table, added nothing to their
  column's narrowest. Word for Windows labs `dr/clip1` and `dr2/g`, `h`,
  `k`:
  - A picture alone in its paragraph is one piece as wide as it, with
    its effect extent and border. Clip1's case C (a 303.75pt picture in
    a 150pt cell with 18pt margins) is now 339.8 / 58.7 (Word 339.77 /
    58.7), and the picture is no longer cut.
  - A nested table counts as its narrowest: each row its cells'
    narrowest, side by side, with their margins
    (`_narrowestTables`, on the child's own layout). A 250pt logo
    beside drawing's banner table leaves the child's column at 177 for
    its 175.5pt picture, at 377.6-553.1 (Word 377.3-552.8).
  - When a picture or a nested table would take the table past its
    column plus its side margins, Word does not grow the table. It
    shares that room out in proportion to the columns' narrowest,
    breaks words ("righ" / "t") and cuts the picture. A 450pt picture
    beside "right cell" in a 467.75pt pct table comes out 445.4 / 22.9
    in Word; ours cuts it at 530.4 (Word 529.8).
    drawing.docx p9's logo (306) beside its banner table (177) is that
    case: the share is 296.3, and Word's print keeps its grid's 296.15.
    Ours cuts at 381.4 (Word 381.12), and the banner ends at 553.0
    (552.72). With 18pt margins (k K2) ours is 2.7pt wide of Word's,
    which seems to share the margins out differently. Text alone still
    takes a table past its column (the 62 "W"s of "Autofit tables").
  - A nested table lays out at its parent's column as fitted, not its
    saved width. A 100% child that the parent narrowed shares the
    narrower column even under its saved grid (`_nestedNarrowed`): in
    lab h's H2 the child's 150pt picture ends at 552.8, as in Word.
  Left: Word re-fits a hand-made grid in proportion to the cells' widest
  settings (dr2/g G1: 409.8 / 58.5 for a 303.75pt picture beside "right
  cell"), and ours keeps the grid where nothing is over. A file Word
  saved holds its own fit. Our nested tables still stand out by their
  cell margin where Word's start at the parent's (G2: 383.6 vs 390.5).
  The 12 corpus documents that nest a table: zh-291fcea7 31.4 -> 32.4,
  the rest unchanged.
  Not an equation (2026-10-22): the reader keeps an Office Math
  equation as an attachment (`m:oMath`, `m:oMathPara`), and ours sets a
  long one on one line where Word breaks it at its operators. Counted
  as a picture, zh-db07d44e's p22 display formula asked its column for
  ~400pt, and the document ran 78 pages to Word's 70 (41.6 -> 16.7,
  found by lenovo-2's sweep). The sweep of this entry covered only the
  nested-table documents. With equations left out it is back at 41.6
  and 70 pages; the other two documents with equations in cells are
  unchanged.

- **A picture is clipped to the cell it overflows (2026-10-22).**
  Word cuts an inline picture wider than its table cell at the cell's
  edge, not at the text's (cell margins do not narrow the cut), and only
  sideways. A right- or centre-justified picture that overflows still
  starts at the left. Body pictures are not cut. On drawing.docx p9 the
  logo now ends at 381.2 (Word 381.12) and the 175.5 pt picture in the
  nested table at 552.8 (Word 552.72). Lab `dr/clip1` (Word for
  Windows): fixed-width cells A, B, D, E and F cut where Word cuts, to
  within 0.5 pt. lenovo-2's sweep found drawing p9 to be the only
  document whose picture bounds change. `RichLayout._clipToCell` wraps
  both paths that paint an inline picture. Left: an autofit table (lab
  case C) grows its column to the picture in Word (339 pt), but our
  `_minContent` counts text only, so a picture-only paragraph adds
  nothing and we cut it instead.

- **A sunburst is drawn (2026-10-22).** chartex's last `cx:` chart,
  a sunburst (`layoutId="sunburst"`), was still its Fallback picture:
  page 3 printed none of its 16 lines. `ChartXML.readSunburst` reads
  each point's categories as a path down a tree (the file lists the
  levels leaf first; a path stops at its first empty name, so chartex's
  "Leaf 6" is a stem with nothing outside it), summing the points under
  one name into one wedge. `ChartPainter._sunburst` draws it as Word's
  print does:
  - The hole and each level are rings of one width (radii 27.5, 55,
    82.6 and 110 pt). The circle is 220 pt across, 1.35 pt above the
    chartex plot's top and 3.15 above its foot.
  - Wedges go clockwise from twelve o'clock, the larger first (258, 165,
    154; children too). Each is its branch's accent, ruled 0.75 pt in
    the background colour.
  - Names are white 8.4 pt, set along the wedge's radius and never
    upside down. They break to four fifths of the ring ("Branc" /
    "h 1"), with the lines' middle 2.1 pt under the ring's.
  - A name shows only where the wedge's inner arc holds its lines plus
    3 pt: Leaf 3's 16.2 pt holds one line, while Leaf 2's 10.8 and
    Leaf 10's 21.7 (two lines) are left bare.

  Word's documents reach it through `ChartXML.readWordChartex`
  (box-and-whisker, then sunburst); Sheets' `readChartex` does not yet
  (chart-sunburst.xlsx, handed to the Sheets session). chartex 77.8% ->
  100.

- **A radar's circle, its labels, as Word and PowerPoint set them
  (2026-10-16).** The radar stood in the middle of its area with a
  label line and 4pt kept on every side, its value labels 4pt off the
  first spoke, and a category label at a spoke's end below or above it
  unless the spoke ran level. Word's prints of chartex's five-spoke
  radar, with its legend at the top, at the foot and deleted (labs on
  the Windows box), fit the whole circle the spokes reach into the
  area: the radius gains half of what the area gains (81.9 to 93.4
  without the legend's 22.9). Over the circle stand 1.2 label lines
  and 3pt, under it 1.2 lines over a foot 6.5pt off the frame (a
  2013-style chart's area ends 9 off it) — which gives Word's radius
  and centre within 0.7pt and PowerPoint's radar-chart's (four spokes,
  18pt labels) within 0.3. A category label beside any spoke not
  straight up or down is centred on its end (chartex's lower two, 7pt
  low; its upper right, 10pt high); the value labels stand off the
  spoke by their size (9.1pt at 9, 18.1 at 18). chartex 61.1% -> 65.3
  (page 2: 10 of 21 lines to 13, the rest its box-and-whisker chart);
  radar-chart 1.74% -> 1.58 in the deck sweep; nothing else moved.

- **A legend at the top stands 4.3pt further under a title
  (2026-10-16).** A top legend was set where the plot would have
  started under the title. In Word's print its baseline is 22.2pt under
  a 14pt title's (chartex's radar chart; its column chart with the
  legend moved to the top, a lab printed on the Windows box), ours 17.9;
  with an 18pt legend 30.3, which the same 4.3 gives. Without a title
  the legend is where ours was (17pt under the frame's top). chartex
  50.0% -> 61 (its page 2: 2 of 21 lines to 10); nothing else moved.
  Left on that lab: with no legend below, Word's category labels stand
  2.5pt lower than ours.

- **A line's legend key is a 19.2pt stroke (2026-10-16).** A line or
  radar chart's legend drew its key in a square's room, a 7pt line
  scaled by the text. Word and PowerPoint draw a 19.2pt stroke whatever
  the text's size (chartex's 9pt legends, line-chart's 18pt one), its
  name 2pt after it; in a row the entry has 3.6pt more before the
  line, so chartex's 9pt entries pitch 60.3pt as Word's (ours were
  43.8, a bar chart's). A legend beside the plot keeps its width, the
  line reaching left out of it: line-chart's plot is where PowerPoint
  has it, its key 1.1pt right of PowerPoint's. No scored line moved;
  the chart decks' scores as they were.

- **A 2013-style chart's ticks take no room from its labels
  (2026-10-16).** Outward tick marks pushed a chart's labels off the
  axis (5.6pt beside a value axis, 8.8 beside a bar chart's categories,
  3.7 below), as PowerPoint draws its 2007-style decks. Word prints
  chartex's 2013-style stock chart with its date axis's ticks out, and
  printed again with them none, and its value axis's out, not a label
  moves (a lab on the Windows box): the push is a 2007-style chart's
  only. Its dates stood 4pt low and the plot 4pt short. chartex 44.4%
  -> 50.0 (page 3: 7 of 27 lines to 11); nothing else moved.

- **A 2013-style bar chart's plot stands half a label line under its
  title (2026-10-16).** A horizontal bar chart's plot started 2pt under
  the title, as PowerPoint's 2007-style bar-chart has it; Word puts a
  2013-style one's half a label line down, as a column chart's (whose
  top value label overhangs it): 61745's bar chart's plot is 17pt under
  its title's baseline in Word's print, as its column chart's, ours
  13. Its categories stepped 59.3pt to Word's 57.7. 61745 94.1% -> 100;
  nothing else moved, the chart decks' scores as they were.

- **A stock chart is read as its lines (2026-10-16).** `c:stockChart`
  (high-low-close) was no chart to the reader, and Writer kept chartex's
  as a grey box. Its series are lines, and Excel writes their lines and
  markers as none: read as a line chart it draws its title, axes, dates
  and legend where Word does, and no series. Its high-low lines and
  up/down bars are not drawn. chartex 34.7% -> 44.4 (its page 3: 0 of 27
  lines to 7); nothing else moved.

- **What goes over of a parting row stands its cells' top margin under
  the rule (2026-10-16).** The part of a row carried to the next page
  was set straight under the rule ruled across its top; Word sets it
  the cell's top margin lower, as the row's first part was, and the part
  is that much taller. zh-9c5d0c3f's road signs (cells with 60-twip
  margins, rows parted under their pictures at page 5's foot) went on
  5pt high of Word's on page 6, and everything under them with them.
  zh-9c5d0c3f 91.8% -> 100 (T17 done); nothing else of ours moved.

- **A picture wider than its line keeps the break after it; before
  2013's layout a space after it goes to a line of its own (2026-10-16).**
  Lab `ps` (Word 16, a fixed cell of 74.35pt, a picture of 60 to 80pt
  then a space, the next paragraph's place read off): in mode 14 a 76 or
  80pt picture followed by a space sets the next paragraph 13.8pt lower
  than the picture alone — the space a line of its own — and not under a
  74pt picture, nor in mode 15. With a `w:br` before the space every
  width takes the line. Ours took it for none of the wide pictures: the
  engine sets a picture wider than the line alone on it and loses a hard
  break after it (lab `bs` shows the break kept after text). A paragraph
  of pictures, spaces and breaks is now laid out as wide as its widest
  picture, which stands at the line's left as before; and before 2013's
  layout a space after such a picture opens a line. zh-9c5d0c3f's road
  signs, 75pt in cells of 74.35, had their captions a line high
  ("車道縮減" 21pt): 90.8% -> 91.8 (T17). Ours still sets the paragraph
  under a picture and a space 2.8pt lower than under the picture alone
  in mode 15, where Word sets both alike — as it did under narrower
  pictures before.

- **A parting row's part on its page centres its centred cells (2026-
  10-16).** Where a row parts at the page's foot, its part there is as
  tall as the most any of its cells keeps on the page, and no shorter
  than the height the row states; a centred cell (or one set at the
  bottom) stands centred in that part. zh-15728c84's row 9, at least
  82.75pt, keeps five 15pt lines of its centred cells on page 3: Word
  sets them 3.9pt down in a part of 83.2, ours set them at the part's
  top. The rules are as they were (the part's rule still runs to the
  foot). zh-15728c84 96.0% -> 98.5; nothing else moved (T32).

- **Unequal columns state their gap on each `w:col` (2026-10-14).**
  zh-25c4de17's two columns are `w:equalWidth="0"` with
  `<w:col w:w="10451" w:space="425"/>` and nothing on `w:cols`; the
  reader took Word's 36pt default gap, so each column came out 7.4pt
  narrower and question 16 wrapped "赠。" where Word squeezes it onto
  one line. The first `w:col`'s gap now stands where `w:cols` states
  none. zh-25c4de17 36.5% -> 100%; nothing else moved by it. Chinese
  sample 82.9%.

- **A picture's line may hang its descent past the page's foot
  (2026-10-14).** On a line grid the picture stands on the baseline
  with its mark's descent under it (above); at a page's foot only the
  picture and the grid's extra above it need the room — zh-90e0cea8's
  last picture ends at its page's usable foot in Word's print, its
  line 2.6pt past it. The descent is the paragraph's page-foot overhang
  (`_overhang`), as a text line's grid extra is. zh-6d1afa56 41.1% ->
  96.8% and Word's 63 pages (its picture paragraphs had each pushed a
  page early); nothing down. zh-90e0cea8 itself still runs a page long:
  ours starts that line about 2pt below Word's (task board T11).
  Chinese sample 83.7%, 60 with Word's page count.

- **A list number's tab goes to the paragraph's own stop first
  (2026-10-14).** Where a hanging number ends before the indent, the
  text starts at the first tab stop of the paragraph's own past the
  number, and only without one at the indent: zh-64044a1d's heading 4
  has a stop at 840 twips and its hanging indent at 851, and Word starts
  "(三) 災害…" at the stop, the line then holding "前" that ours carried
  down. form_footnotes 21.8% -> 46.0%, zh-64044a1d +0.3; nothing down.

- **Lists over one definition share their numbers (2026-10-14).**
  Word counts per `w:abstractNum`, not per `w:numId`: a heading style's
  list and the explicit lists over the same definition number as one,
  and a list's `w:startOverride` restarts its level the first time that
  list is used. zh-64044a1d's heading 3 read 五、 where Word reads 二、
  (list 33 restarts the shared count at 一, the style's list 3 goes on
  from there). The writer keeps the sharing: lists that shared a
  definition point at one, with their restarts and any differing level
  as overrides. NumberingWOver 57.1% -> 100%; nothing down.

- **A centred cell parts with its row, set in the row's part on the
  page (2026-10-14).** Where a row is parted at a page's foot, a cell
  centred (or set at the bottom) whose text all fits the row's part on
  the page is set in that part: zh-64044a1d's "警政組" stands midway
  between the two lines of its neighbour Word keeps on page 20.
  Centred over the whole row, its line lay past the foot, the row could
  not part, and went over whole. zh-69bbcc3c 69.3% -> 86.0% (and
  Word's page count), bug59058 18.9 -> 30.4, bug65649 3.9 -> 6.0,
  zh-15728c84 +1.0, zh-64044a1d +0.7; zh-1a3c7aa0 23.6 -> 23.0 (two
  pages adrift of Word's already by page 15; more of its rows part).

- **A run kept with the next moves from its start, and only when it
  fits a page (2026-10-14).** Word moves a run of `w:keepNext`
  paragraphs to the next page from its first member, and sets a run
  taller than a page as it falls. Ours capped the run at eight and
  weighed it again at every member, so zh-64044a1d (headings 3 and 4
  inherit keep-with-next from heading 1, and its procedures are
  nothing but) put one item on each page: 119 pages to Word's 103.
  zh-64044a1d 34.2% -> 64.5% (101 pages), bug65649 6.0 -> 12.9;
  nothing down.

- **A floating table anchored to the text stands its offset lower
  (2026-10-14).** The editor lays a floating table out in the flow; one
  anchored to the text (`w:vertAnchor="text"`) now starts its
  `w:tblpY` below the text's place, in the flow and on the page.
  zh-64044a1d's equipment list sat 4.35pt high. zh-e6d54ae4 52.1% ->
  62.7%, zh-d68ac84a 76.6 -> 79.9, zh-64044a1d +0.6; nothing down.

- **A run kept with the next goes over from a page's middle whatever
  its length (2026-10-14).** Correcting the entry two above: a run
  that starts below the page's top goes to the next page when it does
  not fit what is left, though no page could hold it, and only a run
  that starts the page is set as it falls. Word sets zh-64044a1d's
  "五、名詞定義" and its run of eleven paragraphs on a new page under
  half a page of room. A kept table row carries the run through:
  bug65649's place-and-date table sits between its title and its
  preamble, all kept, and the title starts the page. zh-64044a1d 65.1%
  -> 72.8%, bug65649 12.9 -> 18.3 (and Word's page count); nothing
  down.

- **What of a parted row goes over is ruled across its top again
  (2026-10-14).** The part of a row carried to the next page starts
  under the row's top rule, as the row did: zh-89385c94's second page
  opens on such a part and its lines stood 0.4pt above Word's, enough
  that a row lower down kept a line at the foot that Word carries
  over. zh-89385c94 16.3% -> 51.0%, zh-8e8d4c40 +1.2; nothing down.

- **Which pages `w:mirrorIndents` mirrors turns on a compatibility
  switch (2026-10-14).** With `doNotFlipMirrorIndents` among the
  file's compatibility settings (Word 2010's files on), the indents are
  as written on odd pages and mirrored on even ones — lab `mirch1`, in
  zh-06c46ba9's package: a first line of 28pt ends every line that
  much short on page 2, not on page 1, with `w:firstLineChars` or
  `w:firstLine` alike. Without it Word flips that: zh-e27cd8bf (no
  compatibility mode) ends its lines 30.6pt short on pages 17 and 19.
  The rule built earlier today was the second half alone.
  zh-06c46ba9 47.2% -> 48.6%; nothing down.

- **A compound cell rule takes all of its room (2026-10-14).** A
  thin line, a gap and a thick one take the width and the other two's:
  Word prints zh-06c46ba9's 1.5pt `thinThickSmallGap` as a 0.72 line,
  a 0.72 gap and a 1.44 line, and the table's row is 3pt taller than
  ours was with the rule counted at 1.5. Small gaps add 1.5pt, medium
  gaps double the width, large ones add 2.25 (the last two after
  LibreOffice's table of Word's widths; only the small gap is in the
  corpus). zh-06c46ba9 +0.4; nothing else has them.

- **Footnotes are set at the foot of their pages (2026-10-14).** The
  file's footnotes were kept for the save and never drawn. Now each is
  read like the body (its own mark showing the number the body's mark
  was given) and laid out at the text's width; paging gives up its
  room, and the separator's, at the foot of the page its mark lands
  on (a paragraph or row that goes over takes its notes along), and
  the page paints Word's separator — a 0.72pt rule 144pt long in its
  own empty paragraph — with the notes under it, the last ending where
  the text area does. zh-06c46ba9's note on page 13 lands within half
  a point of Word's. footnotes and table_footnote 50.0/66.7% -> 100%,
  Bug54849 87.0 -> 91.3, form_footnotes +1.1, bug65649 +0.4.
  zh-06c46ba9 49.0 -> 18.0: its pages to 16 match better, and from 17
  on it is a page out — its table 4 is laid at the 100% it states,
  where Word sets its grid, 11pt wider (task board T14); the notes'
  missing room had hidden that.

- **An autofit table keeps a grid wider than its share (2026-10-14).**
  A table that says it is a share of the column (`w:tblW` in pct) and
  is not fixed, whose grid is wider than that share, keeps the grid:
  the grid is Word's own last fit of it. zh-06c46ba9's table 4 says
  100% of 415.6pt and Word sets its 426.4pt grid, columns where the
  grid has them; scaled down to 415.6, its cells wrapped a line more
  and page 17 on went a page out. A grid narrower than the share is
  still stretched to it. zh-06c46ba9 18.0% -> 74.8%, zh-69bbcc3c +1.6,
  zh-f94d11c5 -0.6 (its columns 1pt over, some nearer Word's and some
  further). Word's autofit proper is task T1.

- **A list number's Latin characters are in the Latin face
  (2026-10-14).** A number with East Asian characters in it was set
  wholly in the East Asian face; Word sets each character in its own
  script's face — the "1" of zh-06c46ba9's "（1）" is Times New Roman's
  7pt, the number fits its 35.45pt hanging indent and the text starts
  at the indent, where at YaHei's 7.8 it ran 0.34pt past and the text
  went to the next tab stop, a character later. Not where the number's
  hint says East Asian (its level's `w:rFonts w:hint`, or the text's
  where the level says none): zh-90e0cea8's "1　" is all SimSun.
  zh-06c46ba9 +1.1; nothing down.

- **A floating chart takes its room like a picture (2026-10-14).**
  Text wrapped round floating pictures only; a chart (kept, and drawn
  as an empty box) was passed over, so the text ran up under it.
  zh-37b6536f's caption stands under its 145pt chart in Word's print,
  where ours stood 29pt into it. zh-37b6536f 30.8% -> 91.5%; nothing
  else has one. (Charts themselves are still not drawn in documents.)

- **Automatic spacing gives way at a cell's edges (2026-10-14).** As
  on a web page, a cell's first paragraph has no automatic space before
  it and its last none after. zh-a4b0f6ea's cover form, every cell auto
  spaced, has its title row 14pt shorter in Word's print than ours
  was. zh-a4b0f6ea 78.4% -> 81.7%; nothing else moved.

- **A list level that states no indents leaves the paragraph's
  (2026-10-14).** Where neither the level nor the paragraph gives a
  left indent but the paragraph gives its first line one, the number
  stands at that first-line indent with the text after it, as Word
  sets it: zh-5901e2b0's "（二）" levels say no indents, the paragraphs
  indent two characters, and the number was drawn in the editor's own
  slot instead — at the margin, its "）" wrapped onto a line of its
  own. zh-5901e2b0 93.4% -> 94.4%; nothing down.

- **A list level of "none" shows no number (2026-10-14).** A level
  whose `w:numFmt` is "none" stands in its own and its sub-levels'
  numbers as nothing. zh-90e0cea8's chapters are "%1%2　" over a level
  0 of "none": Word prints "6　", ours printed "16　", and every heading
  line ran a digit longer. zh-90e0cea8 67.5% -> 88.5%; nothing else
  moved.

- **Contextual spacing compares the paragraph style alone
  (2026-10-14).** Under Word's rules a bulleted List Paragraph and a
  numbered one under it share no space — POI's Numbering had 9pt
  between each of its lists — though not across a cell's edge (a
  table's last list item and a list heading under the table keep
  theirs: zh-06c46ba9). A list of the editor's own still goes by kind.
- **Word 2010's custom number formats (2026-10-14).** A level whose
  format is "custom" (in an `mc:Choice`, over a decimal fallback)
  numbers from its sample: "α, β, γ, ..." runs on through the Greek
  letters, "001, 002, 003, ..." pads digits; a save writes the choice
  back. POI's Numbering 25.0% -> 100% with the entry above; nothing
  else moved.

- **The break after held spaces is in the spaces' own style
  (2026-10-14).** The zero-width space the layout puts after a run of
  spaces it holds (a justified paragraph's, beside East Asian text)
  took the East Asian style of the text after it; its glyph then came
  from that style's Latin base family, whose ascent and descent split
  the em otherwise than the CJK face's, and the line with both grew
  0.9pt at 12pt. zh-799c91cd's "（二）共同申請人同意由" (two runs of
  eight Times New Roman spaces, justified) set its second line 21.55
  under the first where Word has 20.64; lab `spl1`/`spl2`: one space,
  letters, hinted spaces, no-break spaces, or left alignment did not
  do it, two plain spaces did. Giving every inserted zero-width
  character a 1pt flat style instead inflated strutted lines
  everywhere (30 documents down) — only this one site is changed.
  Nothing down; zh-799c91cd's page 1 is now 1pt out, not 2.5 (Word's
  12pt YaHei lines step 20.64/20.4 on its 0.24pt raster, ours 20.65).

- **YaHei's line is 1.715 ems, not 1.72 (2026-10-14).** Word sets
  its 12pt YaHei lines 20.64 and 20.4 apart in a 3:1 mix — its layout
  accumulates a fractional pitch and puts each line on its 0.24pt
  raster — and the mean over zh-7dc3afad, zh-8e8d4c40 and zh-799c91cd
  is 20.58–20.60; ours was a flat 20.65, 0.07 a line, a line's worth
  down a long page. Tried once before (as 1.7157) while the held-space
  bug above still stood, and dropped as net negative; with that fixed
  it is net positive: zh-799c91cd 82.3% -> 91.2%, zh-06c46ba9 76.1 ->
  79.3, zh-232090e0 93.5 -> 97.8, zh-6cd1befe +0.3; zh-7dc3afad 96.4
  -> 92.0 and zh-8e8d4c40 88.8 -> 87.1 (its last two lines now fit
  page 5, where Word carries them to a sixth) — both single page feet
  that Word's raster decides by a fraction of a point.

- **A picture wider than its line keeps its size (2026-10-14).** Under
  Word's rules an inline picture is drawn at the size the file gives
  it and runs past the margin, where the editor shrinks it to the
  line: zh-06c46ba9's fishbone chart is 419pt wide in a 401pt line
  (a hanging indent of 14pt) and Word draws it at 419, 8pt taller
  than ours was, with page 32 and all under it 8pt out. zh-06c46ba9
  79.3% -> 82.5%, bug57031 14.7 -> 24.2, chartex 7.0 -> 32.4; nothing
  down.

- **Every zero-width character the layout puts in is in the Latin
  kind's style (2026-10-14).** The rule two entries above, for the
  break after held spaces, holds for the others too — the break before
  an opening quote or after a closing one, before a loose word's
  characters, the joiner in a Latin word: in the East Asian style the
  glyph is the Latin base family's and the line grows. zh-15728c84
  90.4% -> 90.9%; nothing down. (It is what let the `w:kinsoku` rule
  under this one stand: with the breaks in the East Asian style every
  line of zh-799c91cd grew to 21–22pt.)

- **A paragraph with `w:kinsoku` off may start a line with a closing
  mark and end one with an opening mark (2026-10-14).** The engine
  allows neither, so such a mark that did not fit stayed on its line
  past the margin where Word carries it over; now a break stands
  before each closing mark and after each opening one in such a
  paragraph (the fitter still joins the mark to the character before it
  for its half-em rules). zh-9e08ed28 81.0% -> 81.8%; nothing down.
  zh-799c91cd's "各執1份為憑。", the line that showed the gap, still
  fits in ours where Word wraps the "。" — its width is the open
  question now, not the break.

- **A list number's Latin characters are in the number's Latin face
  whatever the hint (2026-10-14).** Correcting the rule of 4b562bc1,
  which kept a number hinted East Asian wholly in the East Asian
  face: zh-4b8e0abc's "(一)" is hinted so, and Word's print draws its
  parens in Cambria (the paragraph's majorHAnsi) at 0.382 em — 24.7pt
  in all, past the 24.1pt hanging indent, so the tab goes to the next
  default stop (480 twips) and the text starts 9.4pt later than at the
  indent. In the East Asian style the parens were the base family's
  0.333 em, the number fit, and the text started at the indent. The
  number's Latin characters now take the Latin face in every case, at
  that face's own advances (as the text's spans are set); an ascii
  face that is itself East Asian (zh-90e0cea8's 黑体) resolves to that
  face's Latin stand-in. zh-4b8e0abc 88.5% -> 89.2%, its "(一)" lines
  now to the hundredth of a point. zh-90e0cea8 88.5 -> 67.8: its
  "6.1.1" paragraph now wraps as Word's does (its number is narrower,
  the text starts earlier, and "專班。" goes to a second line as in
  Word's print), which sends "6.1.3" over page 5's foot, where Word
  keeps it by the half point our header stands too tall (task board
  T11 — the 黑体/宋体 header's "—" drawn from Liberation Sans). The
  drop is that drift surfacing, not this rule.

- **A dash or an ellipsis in East Asian text is the CJK face's glyph
  (2026-10-14).** The East Asian style is built on the Latin stand-in
  (Liberation Sans) with the CJK glyphs from the engine's fallback; a
  symbol the stand-in has — "—", "―", "…", "–", "─" — came from it,
  with an ascent and descent that split the em otherwise than the CJK
  face's, and a line with it grew. On a Mac such a symbol in an East
  Asian run is now set in PingFang (the fallback itself, named), so its
  metrics are the CJK face's. zh-9c5d0c3f 55.9% -> 66.7%; nothing
  down. (Setting the whole East Asian style's family to PingFang was
  tried first: every hinted ASCII character then took PingFang's
  widths, and zh-457a8d62 fell to 19.9%.) zh-90e0cea8's header, the
  case that pointed here, did not move — its "—" is now the CJK
  face's, and the line still stands 1.09pt under Word's; T11 stays
  open with that.

- **A header's or footer's lines keep to no line grid (2026-10-14).**
  The header and footer sub-layouts took the section's line pitch, and
  a 10.5pt header line was centred in zh-90e0cea8's 15.6pt grid —
  11.44pt under the header's top where Word's print has it 10.35; the
  header was then a point taller, the body's text a point lower on
  every page, and the last picture missed the last page's foot (task
  board T11, chased through the header's "—" and the 黑体 stand-in
  first). zh-90e0cea8 67.8% -> 83.9% and Word's 10 pages; nothing
  down. 63 of 68 documents now have Word's page count.

- **An empty paragraph of an exact line height is that tall
  (2026-10-14).** The engine gives a 0.7pt strut nothing, and
  zh-90e0cea8's two counter paragraphs — 1pt text on 0.7pt exact
  lines, numbered, before each annex heading — took no room: the
  heading stood 1.4pt above Word's print (which draws their 1pt "A"
  numbers 0.72pt apart), and page 8's foot then held a row line that
  Word carries to page 9. zh-90e0cea8 83.9% -> 92.3%; nothing down.
  Its page 8 now matches Word's top and foot to a tenth of a point.

- **A paragraph's last mark neither hangs nor gives its own half, under
  the Traditional Chinese no-break list before Word 2013's layout
  (2026-10-14).** Labs `hang1`–`hang6` in zh-ae3d78ee's package (a
  `w:noLineBreaksBefore` list for `zh-TW`, mode 14): "…你花最多的。" over
  by 1 to 15pt goes to the next line as "的。" with a "？" — which never
  gives — as the line's only other mark, whatever the alignment, line
  spacing, face or kerning; with a "，" on the line the comma gives and
  the mark is taken; with text after the mark in the paragraph it hangs
  in every case. Ours hung it by 4.7pt, and page 28 on ran a line
  short. Only under that list and before mode 15: documents without a
  list hang a last mark as any other (zh-5901e2b0, zh-7dc3afad — the
  unconditioned rule cost them 50 points each), so does the Simplified
  list (zh-a4b0f6ea, `zh-CN`, 81.7% to 30.2 under it) and the
  Traditional one from mode 15 on (zh-4b8e0abc, whose last marks Word
  hangs by 3.5pt). zh-ae3d78ee 84.4% -> 100%, zh-64044a1d 67.5 -> 73.1;
  nothing down.
- **A kept paragraph asks only that the next's first lines stand on
  its page (2026-10-15).** Word's keep-with-next cascades back through
  a run of kept paragraphs — zh-64044a1d's headings 1 to 4 all keep,
  so every run reaches to its chapter's end — but the run moves, from
  its first member, only where a page's foot falls at a member's end
  with the next member's start not fitting after it: its first line,
  two under widow control, all of a short or kept-together paragraph,
  a row. A foot that falls inside a member's own lines breaks no keep
  (Word fills page 72 with one run, the foot in the lines of an item,
  and sends another to page 63 from half a page of room, the foot
  between two), and a member that ends a section ends the run —
  nothing is kept across a section break: "(二)金湖鎮災害應變中心標準
  作業程序" ends page 72 and its section, and the flow chart that
  opens the next stays there. Ours moved the whole run as soon as its
  total did not fit. zh-64044a1d 73.1% -> 87.1, 103 pages as Word's,
  page 72's foot as Word's; zh 90.5 -> 90.7. bug65649 17.7 -> 11.6
  under this alone: the old rule gave an empty kept paragraph that
  carries a section break a page of its own, a blank page Word does
  not have — which had happened to step a layout one page ahead of
  Word's since page 131 back into its numbering. The fix after takes
  that page where Word does, and the count is Word's again.
- **A table row whose first paragraph breaks the page before it opens
  a page (2026-10-15).** A section break on the paragraph before a
  table, the next section opening on a new page, or `w:pageBreakBefore`
  on the row's first paragraph: Word sets the row at a page's head (a
  break character inside a cell it ignores). Ours consulted a
  paragraph's break only outside a row — the importer had put the
  section's break on the table's first paragraph all along — so the
  table ran on. Lab `sectbl` (bug65649's package: a `continuous`
  section's last paragraph "Record of tests:" before a table, the next
  section `nextPage`): Word's table on page 2, ours on 1; the same with
  the section break the plain next-page kind, or `w:pageBreakBefore` in
  the first cell instead. bug65649's test-record table ("Ведомость
  проведения испытаний ИС:", page 131) was the first of its pages a
  page short: 17.7% -> 21.9, 176 pages as Word's. zh-454e2e29 6 -> 7
  pages at 49.3 (a page-break paragraph before its statistics table:
  Word's page 4 opens on the table too; the pages before it have other
  faults). zh-6cd1befe 86.4 -> 85.8, 59 -> 60 pages: Word opens page 53
  on the second table of 附件3 as the break asks, and ours reaches that
  table two rows later — 附件3's section is two unequal columns (T2),
  "附件3" in a 1272-twip column with the title beside it on Word's page
  51, which ours sets a page apart, so the first table ends on page 53
  and the break now costs the page.
- **With `w:wordWrap` off, what may begin a line is the document's
  East Asian language's list (2026-10-15).** Word's Simplified Chinese
  list of characters that may not begin a line holds "%", "'" and ">";
  its Traditional one (`!),.:;?]}¢·–—…`) does not. Ours used the one
  list for both, so a Traditional document's "權重為70%。" could part
  only before the "0": zh-f94d11c5 (`zh-TW`, 332 paragraphs with the
  switch off) has "權重為70" and "%。2.活動參與人次：" in Word's print,
  and "權重為30" over "%。"; ours set "權重為7" over "0%。2.活動參與人".
  The language is the kept `w:noLineBreaksBefore`'s, else the settings'
  `w:themeFontLang`, else the defaults' `w:lang`. zh-f94d11c5 85.9% ->
  86.5, zh-04f73697 96.9 -> 97.3; the ten other `zh-TW` documents with
  the switch off unchanged. (Found on the way: the 6pt gaps either side
  of a digit run in these prints are not the automatic space, which is
  3pt in every lab — labs `asp`, `asp2` from zh-f94d11c5's package —
  but Word's justification of a mixed line, which doubles the
  automatic spaces first and spreads what is left over every gap,
  Latin ones too; ours spreads it over the East Asian gaps alone. And
  zh-04f73697's "本署海巡118報案專線" is a hair: 118.91pt in a cell
  Word gives 118.8 — autofit, T1.)
- **A kept paragraph's footnotes wait for the first paragraph after it
  that does not keep (2026-10-15).** Labs `fn44`, `fn44k`, `fn44k2`,
  `fn44k3` in bug65649's package (44 one-line paragraphs, the first two
  with its footnotes 1 and 2, then its 4-line keep-together 3.7 and
  3.8): with the filler unkept, Word reserves both notes at once and
  3.7 goes over whole; with every paragraph keeping with the next, the
  page fills with text to its foot and both notes stand at the NEXT
  page's foot; with the chain ending at 3.8, the notes take what is
  left under it — footnote 1 parted over the pages, footnote 2 whole
  on the next. So a kept paragraph's notes are not reserved; at the
  first unkept paragraph they are, in order, and one that does not fit
  what is left of the page goes to the next page's foot with those
  after it (not parted: Word parts it, ours sends it over whole, so
  `fn44k2` holds three more body lines on its first page than Word,
  and `fn44k3` sets 3.7 — kept together, unkept with the next — a page
  later; Word sets that one before the notes and parts footnote 1
  under it). bug65649 keeps every clause with the next: its page 3 is
  now Word's, 3.7 whole and 3.8's first line above footnote 1, footnote
  2 at page 4's foot under its reference on page 3; 32.5% -> 37.5 at
  Word's 176 pages. Nothing else in the sample has both.
- **Contextual spacing goes by the paragraph style alone, list or not
  (2026-10-15).** bug65649's "1. Предмет аукциона в электронной
  форме." — a numbered paragraph of no named style, 10pt after,
  contextual — and the plain "Начальная (максимальная) цена контракта"
  under it, contextual too: Word sets them 14pt apart, the 10pt
  dropped between paragraphs of one style; ours kept it, holding a
  numbered paragraph and an unnumbered one for two styles, and every
  line of the page after was 10pt down, the page one line short.
  zh-06c46ba9's "解決建議" (List Paragraph, numbered, 6pt before) under
  an empty List Paragraph (6pt before) is the same case: Word's 56pt
  from the line above, ours had 62. For a document read from a file, a
  neighbour of the same named style and heading level in the same cell
  is the same style, whatever its list; the editor's own unstyled lists
  still go by kind. (A first try also demanded the same cell of plain
  neighbours, which took the long-standing sameness across a cell's
  edge away — zh-1a3c7aa0 76.3% -> 28.6, three pages over; the rule
  only adds sameness now.) bug65649 37.5% -> 42.9, page 12 Word's
  again; zh-06c46ba9 82.7 -> 80.2, a sync loss: its page 42 was already
  a line ahead of Word's at the top, and the 6pt it no longer carries
  lets one line more onto the page, so pages 43 and 44 fall a line out
  of step — the page-42 gap itself is now Word's 56pt.
- **Two list items either side of a cell's edge are not alike
  (2026-10-16).** zh-06c46ba9 p39: "（二）現況分析", a numbered List
  Paragraph of 6pt before (`w:beforeLines` 50), contextual, under a
  table whose last paragraph is a numbered List Paragraph of another
  list: Word's print sets it 9pt below the table's last line box (the
  table's 3 and its own 6), ours 3 — the same-style test held two
  numbered items alike across the edge because their kinds match, and
  dropped the 6. Pages 39-46 ran a line ahead of Word's from there.
  Plain neighbours across an edge stay alike (zh-1a3c7aa0 needs that,
  see above). zh-06c46ba9 78.9 -> 89.5%, zh-84702a67 98.2 -> 99.6,
  zh-abe7e063 98.0 -> 100; zh-69bbcc3c's "五、操作规范" went from 25pt
  high to 5pt low of Word's (one line fewer matched, 99.5 -> 99.4).
- **A first-line count in characters replaces the style's hanging one
  (2026-10-16).** `w:firstLineChars` and `w:hangingChars` are one
  setting, in or out: zh-06c46ba9's style "一" says hangingChars 200,
  and its p70 table's paragraphs say firstLineChars 0 (and firstLine 0)
  — Word's print stands them at the cell's edge, x 63; ours kept the
  style's count beside the paragraph's, read the hanging one first, and
  hung each 28pt out (x 31-33). A paragraph (or a style over its base)
  that names either count now drops both it inherited. The line match
  goes by height and did not move; 87 paragraphs of zh-06c46ba9 and
  zh-64044a1d carry the pair.
- **A line of ideographic spaces alone is its mark's line
  (2026-10-16).** zh-64044a1d p100's form: rows whose cells hold "　"
  alone (style "．表文", 11pt 標楷體 over Times, an 18pt line grid) are
  as tall as its empty rows in Word's print (18.5), its text rows two
  pitches (36). Ours set the U+3000 in the East Asian face, whose 11pt
  line takes two pitches, and the page ran long. A line of spaces alone
  was already its mark's line for U+0020 and tabs ("spaces set no line's
  height"); U+3000 is now one of them, and on such a line is set in the
  run's Latin face, as the mark is. The Mac's lab of the table alone
  (u3k) did not reproduce it; a paragraph alone in the document's own
  style does, on Linux. zh-64044a1d 95.7 -> 97.9%, zh-90e0cea8 96.0 ->
  97.5, zh-84702a67 99.6 -> 100, zh-69bbcc3c 99.4 -> 99.5.
- **Ruby (2026-10-16).** `w:ruby` — furigana over kanji — was skipped
  whole by the reader, base and all: 61470's "東京" under "とうきょう"
  printed a blank page, and a save lost it. Now the base is the run's
  text, in its own runs' looks, and the ruby rides on their style
  (`CharStyle.ruby`: text, size from `w:hps`, raise from `w:hpsRaise`,
  `w:rubyAlign`, and the file's `w:rubyPr`/`w:rt` kept whole, written
  back round the base). Word's print: the ruby's baseline `hpsRaise`
  over the base's; the base spread across a wider ruby as
  distributeSpace sets it (2.75pt between "東" and "京", 1.38 at either
  end: a share between, half a share outside); the line two pitches of
  the 18pt grid where the text alone takes one. Ours: the shares as word
  joiners of that width, the line as much taller over its baseline as
  the ruby stands above the text's ascent (on a grid, whole pitches),
  the ruby drawn over its base after the line (`_paintRuby`); a base
  wider than its ruby spreads the ruby. Within 2pt of Word's both ways;
  61470 0 -> 100%. Not built: rubyAlign other than distributeSpace and
  centre, and ruby in the editor (it is drawn, not editable).
- **A paragraph's trailing spaces after ideographs take the
  ideographs' face (2026-10-16).** zh-1563bd74's footer: "X" in 16pt
  Calibri on a line of its own, then "红河县人民政府发布" and five spaces
  in 14pt bold 宋体. The Mac's lab `hfl` (Word 16, the paragraph in the
  body four ways): the spaces make it no taller (52.56 with them, 52.80
  without). Ours set them in the square face's Latin stand-in (Liberation
  Mono at 5/6), whose ascent and descent split the line otherwise than
  the platform's CJK fallback; the engine took the deeper of each, 14.58
  above from Noto Sans CJK and 4.82 below from the mono, and the line
  stood 19.4pt for 18.2 on Linux (18.6 on the Mac, its fallback nearer
  the mono's split). The footer ran 0.8pt tall, and page 25's last empty
  line went over: from there every page a line late, 30 pages to Word's
  29. Now the spaces that end a paragraph after ideographs, in a run
  whose Latin letters stand in for an East Asian face's, are set in the
  ideographs' face at the stand-in's width. zh-1563bd74 88.6 -> 99.7%,
  Word's 29 pages; nothing else moved. (All spaces after ideographs, mid
  line too, was tried first: the line fitting measures those otherwise,
  and zh-232090e0 95.7 -> 4.3, zh-2b955411 98 -> 34.5 and four more
  collapsed.)
- **The mark under a nested table is half a point; a short picture's
  line is its mark's (2026-10-16).** drawing.docx p8-11. Word's print
  (clipped glyphs kept) holds exactly five spans of 0.48pt, four Verdana
  and one Arial, and the file exactly five empty paragraphs that end a
  cell right under a nested table, their marks 8.5pt: such a mark is set
  at half a point (`RichParagraphStyle.markUnderNestedTable`, flagged by
  the reader from the file's shape and not written back). Ours set them
  at 8.5, and page 8's foot ran 26pt long (T39's try of no line at all
  overshot on page 11). That done, page 9 opened 5.8pt high: a paragraph
  of one 0.75x4.5pt picture under five empty ones is, in Word, the line
  of its 9pt Times mark (10.35pt) with the picture at its foot — the
  Mac's lab t50: without the picture the same, a 12pt mark lowers both
  by 3.45, a 12pt picture is its own height. At single spacing: bug59058's
  11.25pt picture under an 11pt Calibri mark, in 1.15 lines, stands
  2.18pt down (13.43, Calibri's single line), the multiple's extra under
  it as under text. Off the line grid, which has its own rule. drawing
  89.7 -> 98.1%; nothing else moved.
- **Space is shared across a hidden paragraph (2026-10-16).**
  drawing.docx p11: "…ОАО "ПО Водоканал г. Ростова-на-Дону"." ("text",
  14pt after, automatic), an empty paragraph whose mark is hidden
  (`w:vanish`), then the heading "ИА Regnum" (12pt before). Word's print
  sets the heading's baseline 28.8 under the text's, the larger space
  alone; ours hid the paragraph but shared the heading's space with it,
  had both spaces, 40.75, and the page lost its foot. The space a
  paragraph shares is now the nearest shown paragraph's above it.
  drawing 98.1 -> 100%; nothing else moved.
- **A document with comments or tracked changes prints with its markup
  (2026-10-16, the user's call: keep Word's behaviour).** Word prints
  such a document with its balloons by default, and POI's six references
  are those prints. Measured off them: the page and a markup area 3.7in
  wide from its text's right edge are scaled together to the paper's
  width with 36.5pt to spare (k 0.693-0.737), the page 8.6pt from the
  paper's left and 5.2pt under the middle top to bottom; a grey pane
  from 9.1pt past the text, 257.3pt wide (unscaled). Balloons stand from
  32.1 to 262.4pt past the text, their tops level with their anchors'
  lines, stacked down; each joined to its anchor by a line along under
  it. Comments ("Commented [ab1]:", numbered through the document) in a
  serif at 9pt; deletions ("Deleted:", the text in its own face, a
  deleted mark as ¶ — and gone from the page, a paragraph whose mark is
  deleted joined to the next) and formatting changes ("Formatted:
  English (US)", "Font color: Auto", "Font: Bold") in the document's
  Balloon Text, else Word's own (Tahoma 8pt). `PdfExport.MarkupFrame`,
  `PdfMarkup`. comment, testComment, 58067 0 -> 100%, delins 3.3 -> 23.3,
  WordWithAttachments 5.3 -> 23.7, the POI mean +1.9; nothing else moved.
  Then (same day): "Field Code Changed" where a field's result begins
  when its code was reformatted (`CharStyle.fieldCodeChanged`, flagged by
  the reader, not saved), before the result's own balloon; balloons
  stacked edge to edge (delins's one-line ones 15.1pt apart), a
  deletion's text 8.8pt further in. delins 50 -> 55%.
  Then: moved text. The reader skipped `w:moveTo`/`w:moveFrom` whole, so
  moved text was gone from the page and from a save. The new place now
  reads as an insertion and the old as a deletion, both marked `moved`
  (saved as w:ins/w:del); printing labels them "Moved (insertion) [n]"
  and "Moved down/up [n]:". No score moved (Tika-792 still 0: Word's
  "Formatted: Font color: Auto" and the balloon order differ).
  Then delins's balloons, read off the connector lines in Word's print
  (each balloon's line runs to its anchor): a reformatted paragraph mark
  has its "Formatted:" balloon, but joined to the stretch it ends and to
  the next paragraph's first runs (three headings and their marks, one
  balloon); a field's start and end break a stretch, so a link's text and
  the words after it are two (`CharStyle.fieldResult`, read, not saved).
  A deletion's balloon starts each deleted paragraph on a line of its
  own, a list item's with "<#>" for its lost number. delins 55 -> 75%,
  its 23 "Formatted:" and 10 "Field Code Changed" as Word's; nothing else
  moved. Open: Word prints "Field Code Changed" first for links 13-15
  and last for 16-21, and the only difference in their XML is 13-15's
  reformatted marks — one file does not say why.
  Not built: change bars in the margin, the comment
  range's tint in its author's colour.
- **A VML drawing canvas in the line holds its text box at its place
  (2026-10-17).** WordWithAttachments' "Словарь/dictionary/Луғат" is a
  `v:group` (a drawing canvas, 126x99pt) in the line, its text box a
  shape placed absolutely in the group's coordinates. The reader took
  the first `v:shape` anywhere in a drawing for its float and its size:
  the inner box floated the whole canvas, which took no room (and was
  read as 1976 by 1533pt). Now the outermost VML element decides both
  (`_vmlTop`), and a group's text box sets its text at the box's place
  in the group (`_vmlTextPlace`, VML's 7.2/3.6pt insets). 23.7 -> 84.2%,
  nothing else moved.
- **An embedded object prints its icon (2026-10-17).** An OLE object
  shows the WMF or EMF its `v:imagedata` names, and Writer played it
  with no image provider: the caption printed, the icon — a bitmap in
  the metafile (DibStretchBlt, AlphaBlend) — did not. `WriterMetafiles`
  now decodes a metafile's bitmaps as the layout does its pictures, and
  the PDF export waits for them. WordWithAttachments' package and Word
  document icons and tika-3388's .msg icon print as in Word's. No score
  moved.
- **A comment's balloon hangs at the comment's end (2026-10-17).**
  WordWithAttachments' comments each cover a quatrain; Word's balloons
  stand level with the quatrains' last lines, where the references are,
  and ours stood with their first. Anchored at the range's end now. No
  score moved. Not modelled: Word prints no balloon for its first
  comment (its reference alone in an empty paragraph) yet numbers the
  others from 2.
- **楷体_GB2312 is YaHei to today's Word for Mac (2026-10-17).** The
  first zh sample's prints (2026-10-12) set it in KaiTi; Word 16.113.3
  sets it in Microsoft YaHei, alt name or not, and the Mac reprinted all
  68 with it (db1a7940). The mac font mode now stands YaHei in for it,
  as for 仿宋_GB2312. zh-e02b0479 68.6 -> 97.1%, zh-15728c84 86.9 -> 98.5,
  zh-232090e0 86.7 -> 95.6; nothing down.
- **A multiple's extra space may hang past the page's foot; a page
  break in a table cell is nothing (2026-10-17).** Off the grid, Word
  sets a line's 1.5 or double spacing under its text, and the page's
  last line may reach past the margin by that much, as a grid line's
  half leading may: zh-8112041b's page 2 keeps four empty 1.5-spaced
  16pt paragraphs under its articles, the fourth's 36pt line 5pt past
  the margin, its 24pt of text inside. Ours took three. Its form's
  title cell opens with two page breaks, which Word's print shows as
  nothing; ours split an empty line off. zh-8112041b 70.8 -> 100%,
  nothing else moved.
- **Web spacing parts two lists (2026-10-16).** delins: bullets with
  automatic spacing (beforeAutospacing/afterAutospacing), "A name in
  various Indian languages…" of numId 1, then a nested bullet of numId 2:
  Word sets them the web's 14pt apart, ours none, taking them for one
  list because both are bullets. One list is now the same numbering
  (`listId`) where the file names one, the kind only for the editor's
  own; and an item's automatic space after is none only where an item
  of its own list follows. bug57031 94.4 -> 100%, delins 23.3 -> 35.0;
  nothing else moved.
- **A Symbol bullet's line is at the bullet's own size (2026-10-16).**
  The level's face reaches a list line through a zero-width space set
  in it (form_footnotes: Symbol bullets make 10pt text's lines 12.24).
  That space took the text's size: delins's 10pt Symbol bullets under
  12pt Times made a 14.7pt line where Word's is the text's 13.8, each
  bullet 0.9pt (scaled 0.6) taller. Now at the level's own size where it
  says one. delins 35 -> 50%; nothing else moved.
- **A paragraph that opens with a tab stays at its indent (2026-10-16).**
  A tab is widened by spacing on the tab itself, and the engine sets a
  character's spacing half before it: at a line's start that moved the
  whole line on by half the tab. WordWithAttachments' header,
  "<tab>Страница 1" on a centre stop at 233.85pt, stood 101pt right of
  Word's. Slides already put a leading tab's widening into the first
  line's indent box (HowWeRefactor); documents now do too. The header
  within 2.4pt of Word's; no score moved (the line match goes by height),
  zh-6cd1befe and zh-7dc3afad a line each way (a line opening with a tab
  now has its indent box, in its first run's face).
- **A tab stop nearer than the engine's own tab width makes the tab
  that narrow (2026-10-15).** bug65649's "5.1.1.<tab>Гарантийный срок
  на материалы…": the number ends 1.35pt before the stop at 1134
  twips, and Word's text starts at the stop (141.66 in its print);
  ours kept the engine's 3pt tab (text at 143.40), and with 1.65pt
  less the line's nine spaces had 0.87pt each to give for
  "выполнения" — past the quarter they may — so it went over, where
  Word's print has them at 2.31 and the line filled to the margin
  exactly. A left tab's adjustment may now be negative down to half a
  point of width; the aligned kinds keep their floor at nothing.
  (Below the sweep's 0.3-point threshold on its own; the page is
  Word's line for line now.)
- **A line may part after a hyphen before a digit, outside East Asian
  layout (2026-10-15).** Lab `hy3` in bug65649's package (34 right
  indents, 1.75pt apart, Times New Roman): where a line ends inside
  "КС-2", "А-5" or "2024-10" Word parts it after the hyphen — "КС-" |
  "2).", "2024-" | "10)." — never before it; the engine, keeping a
  number whole with its sign (`_glued`), takes "КС-2)." over whole.
  bug65649's page 14 "(форма № КС-" / "2)." is Word's now; 42.9% ->
  43.3. Not under East Asian layout: zh-64044a1d's contact table
  holds "0988-228598" in a cell too narrow for it, and Word parts it
  after the tenth digit, not at the hyphen (its print, YaHei digits
  7.04pt as ours); the rule on, ours parted "0988-" | "228598" and
  "332-" | "529", the row grew, 88.6 -> 83.0. Lab `hyz` in that
  package (標楷體, mode 11) could not tell — its Chinese text always
  offered the line a break elsewhere — so the East Asian side stands
  on the document alone.
- **A cell's text keeps clear of its side lines (2026-10-15).** Labs
  `cb`, `cb2`, `cb3` in bug65649's package (fixed cells, Times New
  Roman 11pt, a left-aligned and a right-aligned "H"; PyMuPDF for the
  x of each): the text's left edge stands the margin and half the
  line's width in, and never inside the line — at a 108-twip margin
  a 1pt line sets it 0.48pt further in than no line, a 3pt line 1.44,
  a 12pt line 6.48; at 28 twips a 6pt line sets it 6pt in, the margin
  lost under it — and the right inset is the margin less half the
  line, the right-aligned "H" ending half a point nearer the edge per
  point of line: under ordinary margins the text is shifted, not
  narrowed. With no margin the text loses the whole line: "зарплаты"
  in a 1060-twip cell under 85-twip paragraph indents wraps "зарплат"
  / "ы" from a 1.5pt line on, fits under a 1pt one, and fits again at
  1080 twips. bug65649's estimate tables (pages 22 on, 150 of them)
  are such cells — no cell margins, 1.5pt lines, 85-twip indents —
  and their header cells wrapped a character short of Word's. The
  lines are the cell's own side over the table's (its edge for a side
  column, its inside one for the rest), as the rules above and below
  are resolved; `c.borders` is the editor's and empty for a file.
  Labs `cb` and `cb3` replay through ours within 0.1pt at every
  width. bug65649 43.3% -> 53.8, zh-f94d11c5 86.5 -> 98.5 (its
  `wordWrap`-off cells had been a hair wide), zh-04f73697 97.3 ->
  97.9; zh 90.7 -> 90.9. Down a hair: zh-e061a08e 91.8 -> 91.0 (a
  zero-margin cell under 0.5pt lines loses "÷" from a line Word
  holds — Word's cell is that hair wider, a percentage width) and
  zh-53fa3030 97.8 -> 97.4 (its page 3 cell now wraps "民政業務" alone
  as Word's does; the loss is further on).
- **A row set whole at a page's foot has room for the line under it
  (2026-10-15).** bug65649's estimate tables pair a 24.65pt row with
  a 13.85pt unit row ("м") under it, ruled only above each pair; on
  page 26 the last unit row has 0.6pt of room left under it, and
  Word opens page 27 with it. The row baselines are Word's to 0.1pt
  all the way down the page (PyMuPDF), so what Word asks is the
  0.75pt line it draws under a row that ends a page — the next row's
  top one, or the row's own bottom one — and ours had asked the row's
  own top line again, which a unit row has not. `ruleNext` is
  resolved beside the rules above and below; a parted row's piece
  keeps asking its own top line's width as before (zh-e061a08e's
  page 4 parts a row under a thicker line exactly where Word does,
  and asking the thicker line there lost a line: 91.0 -> 89.0 in the
  first try). `STARLING_RICHTEXT_ROWS=<page>` now prints each row set
  on a page — where it stands, what is left, what it asks — which is
  how this was found. bug65649 53.8% -> 58.1.
- **Word's symbol faces keep their own lines (2026-10-15).** Word's
  bundled `symbol.ttf` has an hhea ascent of 1.005 and descent of
  0.220 ems (its Wingdings .899/.211, Wingdings 2 .843/.211,
  Wingdings 3 .928/.211; the Mac's own Symbol.ttf is .701/.299, a
  different face), so a line with a Symbol glyph on it — a `w:sym`
  box, a bullet from a Symbol-faced list level — is 1.225 ems tall.
  form_footnotes: its 10pt lines with a Symbol box or bullet are
  12.24pt apart in Word's print (PyMuPDF baselines), ours were 11.5,
  the clone's; four such lines put our page 1 four points short, the
  "H - Observações / I - Assinaturas" row — Word's page 2's first —
  on page 1, and the instructions off page 3. The resolved face for
  those four names carries the height and baseline; a `w:sym` run
  takes it as its own face, and a list paragraph whose level names
  one of them takes it on its first line through a zero-width space
  in that face before the text (the box before the text sets no line
  height of its own). Only the symbol faces: the space before every
  list paragraph's text, in whatever face, cost zh-90e0cea8 20 points
  — the first character's place is read by more than the offset map,
  a trap left for whoever needs a level's face on the line in general.
  form_footnotes 47.1% -> 48.3, its Symbol lines 12.25 now; still two
  pages to Word's three — the "D - ☐ Concessão" row is 1.5pt short of
  Word's yet, the Symbol glyph's own ascent not placing the baseline.
  (delins 5.0 -> 3.3 is its Symbol bullets 12.25 apart in a Word print
  that is a scaled markup-balloon page, not a layout.)
- **A table that states its cell spacing rules each row top and
  bottom (2026-10-15).** The web's separated borders: a table with
  `w:tblCellSpacing`, even of nothing — every HTML-converted table
  has it — draws each cell's own four lines, so a row has its bottom
  line under its own top one and stands a line taller than a
  collapsed table's row, which shares one line with the row below.
  Lab `ob2` in bug59058's package (Word 16): rows of 12pt text under
  75-twip margins stand 23.36pt apart with no lines and 24.88 with
  0.75pt ones, single or outset alike — twice the line, where ours
  added it once (24.10); bug65649's estimate tables, which state no
  spacing, share theirs, half a line a row, as before. bug59058's
  state list (29 rows, 0.75pt outset lines) had a row more on its
  page 4 than Word's: 45.8% -> 47.2, still a page short. A row ruled
  so has its bottom line in its own height and asks nothing under it.
- **The space after and the space before share their room across a
  paragraph border too (2026-10-15).** Labs `sp`, `sp2`, `sp3` in
  bug59058's package (Word 16, 12pt text on 15pt lines): 9pt after
  over 9pt before is 24.00 between the lines — 15 and the one 9;
  18 over 9, 9 over 18, 12 over 6 and 6 over 12 all take the larger
  alone; and a bottom line on the first paragraph or a top one on the
  second changes nothing of that, adding only its own width and
  `w:space` — 24.48 for a top line, 25.44 for a bottom and a top,
  28.56 for a line 4pt off, 33.36 for two. Ours had kept the two
  spaces whole across a border (`_sharedSpace`'s guard from
  b388f95c, an assumption), so bug59058's "Abstract" — ruled under,
  9pt after — stood 9pt further from its body than Word sets it, and
  page 24 lost its last line, the page after it a line out of step:
  47.2% -> 52.1, and Word's 52 pages (POI 104 of 111 page counts).
- **A piece that goes on from a line's cut starts a pixel under it
  (2026-10-15).** The engine's line boxes are whole pixels and the
  glyphs' ink is not, so the descenders of a page's last line reach a
  hair past its cut, and the piece on the next page — clipped from
  that cut — drew their tips again at its head: bug59058's page 25
  opened with the bottoms of "g g y" from page 24's "including an
  ecologic analysis", a strip a pixel tall over the first line, which
  PDFKit reads as a line of text "ggy" there (PyMuPDF, which keeps to
  the clip, sees nothing). Twenty-eight of its pages had one. The
  continuation piece's clip now starts 0.75pt under the cut; a first
  or whole piece is as it was. No score moved by 0.3 — the phantom
  rows matched nothing and cost only their count.
- **A Latin name Word has no face for goes by the font table
  (2026-10-15).** bug59058's body is "MinionPro-Regular", 13pt, which
  Word's print sets in Cambria — not the Times New Roman its font
  table names as the alternate — and ours set in Liberation Sans,
  wrapping differently on every line of 52 pages. Labs `fs`, `fs2`,
  `fs3` (Word 16 for Mac; bug59058's package and two of other
  themes, `fs3` with entries written into the font table): a table
  entry with an alternate and a PANOSE that is not all zeros, or
  none, is set in the alternate (`agencyr` → Times New Roman, `TestD`
  and `TestE` → Arial); an entry whose PANOSE is all zeros keeps no
  alternate and goes by family — roman is Cambria (MinionPro-Regular,
  MinionPro-It, "inherit"), auto is Calibri (`TestB`); an entry with
  neither alternate nor PANOSE is Calibri whatever its family (`xits-
  math`, `TestC` swiss, `TestF` auto — and "S宋体", measured before);
  and a name the table does not hold is Cambria in a file of any
  theme (FooSerif Book, BarSans Light, under Cambria/Calibri, Arial
  and Aptos themes alike). `substitute` ends so for a name Word on a
  Mac has no face for — not one of the 577 families it bundles or
  the Mac holds (`wordMacFamilies`, read off this box), and not an
  East Asian name set for Latin characters (zh-6d1afa56's "√" in
  仿宋 is FangSong's in the print; the rule unguarded set it in
  Calibri, 96.8% -> 94.3, and "Lucida Sans Unicode" in Caladea,
  failing its test) — in place of "declared Latin → Calibri, else
  Liberation Sans"; the importer notes each entry's alternate, family
  and PANOSE. Caladea's advances are Cambria's to the unit, so
  bug59058's MinionPro runs wrap as Word's: 52.1% -> 53.3 (its bulk
  is "Times" and the theme's Calibri, which were right already).
  (Unguarded, SampleDoc had jumped 50 -> 66.7 by accident: its Arial
  Black in Carlito happened to wrap as Word's Arial Black; a width
  model for Arial Black is the honest fix.)
- **A stop before a bracket is one word with it (2026-10-15).**
  bug59058's "…particular outcome or population.(4)Temporality: the
  potential…" has no spaces round "(4)": Word, which parts Latin text
  at spaces and after hyphens alone, carries "population.(4)Temporality:"
  over whole and leaves the line ten words long; the engine, by
  Unicode's rules, may break after a stop before an opening bracket,
  so ours kept "population." on the line and parted the rest — a line
  out of step for the page. `_joinsLatin` now joins a stop, comma,
  colon or semicolon to an opening bracket after it with a word
  joiner, as it already did the slash, the question and exclamation
  marks, the bar and the closing brackets. bug59058 53.3% -> 56.3;
  nothing else moved.
- **The hyphenation point "‧" is an em in a square face
  (2026-10-15).** zh-190d730c (`zh-TW`, PMingLiU, `wordWrap` off)
  writes "亞洲‧矽谷" with U+2027, which PMingLiU sets an em wide (its
  hmtx: 1.0, as the bullet and the two-dot leader; "·" U+00B7 is
  0.206). Ours drew it from a fallback at 6.2pt, so each such line
  held a character more than Word's, and the justified text ran a
  character ahead from page 4 on. The em rule for symbols an East
  Asian face sets (`fullWidthSymbols`, ■→ arrows) now takes U+2027
  and U+2025 whichever kind the layout counts them, and U+2022 in an
  East Asian run. zh-190d730c 43.4% -> 97.8; zh 91.5 -> 92.3; nothing
  down.
- **A centred cell in a parted row stands midway in the part on the
  page (2026-10-15).** c2542ff6 set a centred cell in the part only
  where centring in the whole row would have put it over the foot;
  Word does it wherever the row parts, and the part is as tall as what
  the row's other cells keep on the page — their last kept line and
  margin — not the room to the foot (Word draws the part's bottom rule
  there). zh-1a3c7aa0's row "65" on page 22: Word's number at 169.7,
  ours at 145 centred in the whole row, 162 centred to the foot, 169
  now; its page-51 "127" is the same case (the Windows box's lead).
  zh-abe7e063 91.4% -> 98.3, zh-1a3c7aa0 76.3 -> 78.0, zh-69bbcc3c and
  zh-84702a67 +0.5; nothing down.
- **A line may part between a closing curly quote and a hyphen
  (2026-10-15).** zh-84702a67's "…建筑市场监管系统”-“企业信息备案模块”"
  ends a line with "统”" and opens the next with "-“企业" in Word's
  print: Word's Simplified Chinese list keeps neither a hyphen from a
  line's start nor a quote's other side here. The engine parts on
  neither side of a quote, and `_breaksBetween` let a closing quote
  part only from what is wide — so ours carried "统”-“企" as one piece
  and the line ran a character short, page 3 on. zh-84702a67 88.3% ->
  91.5; nothing else moved.
- **From 2013's layout on the automatic spaces give in the body too
  (2026-10-15).** zh-4b8e0abc (mode 15, 標楷體 14pt, justified) holds
  "…各辦理1次PCR(共" on one line in Word's print, 12.1pt over at the
  natural widths: its full-width "：" is set at its half (7pt) and the
  four automatic spaces between ideographs and Latin (理|1, 1|次,
  次|P, R|及) at 2.3 of their 3.5 — the marks first, the spaces what
  is still needed, as lab `ovc` found for a cell before 2013's layout.
  The fitter let the spaces give only before that layout; from it on
  they now give outside cells too (cells keep the older finding). The
  modern taken-test is unchanged. zh-4b8e0abc 89.2% -> 96.6,
  zh-33aa9899 98.6 -> 99.0; nothing down (clean A/B, n172 vs n171).
- **Open, measured (2026-10-15): a squeeze Word refuses on a line with
  Latin quotes.** zh-1563bd74 (mode 14, 16pt, YaHei for 方正仿宋_GBK)
  has a line "“因灾房屋…无房可住、无生活来源和自救能力”" that Word leaves
  without "的", 3.95pt over with one "、" — the legacy half-em rule
  takes it. Lab `sq15` (variants of that paragraph, in
  ~/starling-word-check/lab/in): the same with "，" or "。" for "、", in
  宋体, without `w:snapToGrid` or `w:textAlignment`: refused; the
  opening quote as '"' (3.38 over): taken; as '^' (4.36) or '~':
  refused; either quote as ASCII ")" or "(" (2.15): taken; no quotes and
  an ideograph more (5.75, no Latin on the line): taken. So with Latin
  on the line the limit falls between 3.38 and 3.95 — about a quarter
  em. Tried as a rule: for any Latin character on the line it cost 24
  documents up to 64 points (digits are everywhere); for curly quotes
  alone it moved nothing it was meant to and cost zh-6c568ae9 1.3 and
  zh-d68ac84a 0.8. Not built; the rule is narrower than either.
  Settled the same day (Windows box): the limit is half of the character
  BEFORE the one taken — here the 7.1pt quote — not of its own em; see
  "Before 2013's layout the next character is taken half the one before
  it over" above.
- **Arial Black at its own widths (2026-10-15).** Word has Arial Black
  (its DFonts' ariblk.ttf); ours drew it as the sans stand-in at the
  stand-in's widths, some 15% narrower letter for letter, so SampleDoc's
  16pt heading broke a word later than Word's. The resolved face now
  carries Arial Black's advances for U+0020–U+007E and its line (1.41
  ems by its hhea, the ascent 1.1006), as Verdana's and YaHei's do.
  SampleDoc 50% -> 100; nothing else moved.
- **A CJK compatibility ideograph Word sets in Noto Sans SC makes its
  line taller (2026-10-15).** Word on a Mac sets most Chinese face
  names in YaHei, which has 21 of the 512 compatibility ideographs
  (U+F900–FAFF); for the rest its fallback takes Heiti SC or Noto Sans
  SC. Lab `cj2` (every one of the 60 the Chinese sample uses, a line
  each, 標楷體 → YaHei 12pt): 26 go to Noto Sans SC ("行" U+FA08, "理"
  U+F9E4, "狀" U+F9FA …), and their line stands 1.44pt lower under the
  line above and 0.48pt deeper over the next — Noto's hhea 1.16 + 0.288
  ems with Word's 30% more; the 34 in Heiti SC change nothing. The
  layout now puts a word joiner in Noto Sans SC before each such
  character where the run's East Asian face is YaHei
  (`lacksCompatibilityIdeographs`), so the line takes Noto's height; the
  extra goes below the line rather than split 1.44/0.48 as in Word, the
  sum the same. Noto Sans SC is installed in this Mac's user fonts, so
  this models the machine the prints were made on. Ungated, a
  PMingLiU document's own compatibility glyphs (zh-db93607e) took the
  height too, 99.2% -> 4.9. zh-7dc3afad 92.2% -> 98.9, zh-8e8d4c40 87.1
  -> 90.4 at Word's 6 pages; nothing down.
- **In a cell before 2013's layout, a Latin word on a line without
  spaces is taken only half an em over (2026-10-15).** Lab `ovc`
  found Word taking a Latin word in a cell whenever the marks and
  automatic spaces could give what it needed — on a line of 41 spaces.
  Lab `sqc` (zh-69bbcc3c's cell "3月，6月，9月，11月", 12pt, mode 14,
  the cell's width varied; the other Mac session's find): "11" is taken
  4.5pt over and left from 6.0, with "，", "：" or "、" as the marks —
  though they could give 18pt. So the room test now holds for a word
  on a line with a space character on it (`lineBlank`) or a word that
  carries a full-width mark of its own (zh-06c46ba9's "1）" is taken
  9pt over in Word's print); otherwise a Latin word in a cell is taken
  within half an em. zh-69bbcc3c's two such cells (pages 22, 31) wrap
  as Word's; +0.2, nothing down.
- **Under the zh-TW list the last mark gives where another mark gives
  (2026-10-15).** 74e2f9f0 had a paragraph's last mark neither hang nor
  give under Traditional Chinese's no-break list before mode 15 (labs
  `hang1`–`hang6`, whose lines held a "？" that gives nothing).
  zh-64044a1d's "…限制或禁止民眾進入或命其離去措施事宜。" is 6.15pt over
  with one "，" on the line, and Word's print sets that comma 3.1pt and
  the final "。" 3.0pt narrower: the last mark gives its share where
  another mark on the line gives too. Letting it give always cost
  zh-ae3d78ee 15.6 points (its lines are the labs'). zh-64044a1d 88.8%
  -> 90.3; nothing down.
- **A closing mark before a full-width opening quote gives its half
  (2026-10-15).** zh-15728c84 (mode 14, compressPunctuation, quotes in
  runs hinted East Asian) writes "政务微博微信、“12345”热线": Word's print
  sets "、" 5pt wide at 10.1pt — half its em, as before any opening
  mark — and the "“" its em; ours set "、" whole, and the line held a
  character less, then the page. The span and the fitter both take a
  full-width “ or ‘ after a closing mark as an opening mark for the
  half-em rule. zh-15728c84 90.9% -> 93.4; nothing down (clean A/B).
- **Endnote marks count "i, ii, iii" (2026-10-15).** Word's endnotes are
  numbered in lower-case Roman numerals unless `w:endnotePr` in the
  settings names another `w:numFmt`; its footnotes in digits.
  endnotes.docx and Bug54849 show "i" in Word's print where ours drew
  "1". The settings' formats are read for both kinds. No score moved
  by the sweep's 0.3; the endnotes themselves are still not set at the
  document's end (two documents in the corpora have one each).
- **A centred cell that does not fit a row's part is parted from its
  text's top (2026-10-15).** zh-1a3c7aa0's row 328 (every cell
  centred, the name "硝酸铵[含可燃物>0.2%,包括以碳计算的任何有机物,但不包括
  任何其它添加剂]" three lines in a 305pt row): Word starts the row on
  page 82 with two lines of the name at the head of the part and the
  third on page 83. Ours parted the cell where the flow centres it,
  its first line 133pt down with 92.7 left, so the row went over
  whole. Now, in a row begun under other text, a centred (or bottom-
  set) cell that cannot stand whole in the part is parted from its
  text's top, at the part's head — where a line of it fits there.
  Where none does, what goes over stays centred over the page as the
  flow has it (zh-e37f8d40's "乡镇社会事务办公室核查意见", which went to the
  top of its part and lost 1.9 points otherwise), and a row that then
  goes over whole is centred again (bib-chernigovka, −0.9 before).
  Not before mode 12: zh-64044a1d (mode 11) takes its "電力組" row over
  whole with a line of each cell fitting at page 19's foot — the cause
  is not known; seen in modes 12 and 15. zh-1a3c7aa0 91.7% -> 98.1,
  bug65649 58.4 -> 67.8; nothing down.
- **A word wider than its cell's line opens a line of its own
  (2026-10-15).** bug65649's unit cell "1 направление" is 49pt wide and
  the word 55: Word's print has "1" / "направлен" / "ие" — the word
  taken to a new line, then parted by characters — where the engine
  parts it where the first line runs out, "1 направле" / "ние". The
  estimate rows below were a line out of step from page 58 on. Now a
  word (three letters or more, no ideographs) that follows a space in
  a cell narrower than 150pt and is wider than the cell's line starts
  a line of its own, through a line separator put in before it.
  (A hyphenated word is measured up to its first hyphen, which a line
  may end with: Word sets "Блок разветвительно-" / "изолирующий"; the
  whole compound measured, "разветвительно-" had taken a line of its
  own — bug65649 83.8 -> 84.1.)
- **Paragraphs of one border set share one box (2026-10-15).** Word
  groups consecutive paragraphs whose borders and indents are the same
  (in the same cell): the top line over the first, the bottom one under
  the last, and no room for either between them. bug65649's
  specification lines, each with a grey 0.5pt bottom border, stand
  12.5pt apart in Word's print (their "at least" 12.5); ours gave each
  its own bottom line and its room, 13.0 a line, and from page 72 the
  estimate tables ran long. Layout and painter both skip a border edge
  a neighbour of the same set joins. bug65649 84.1% -> 96.4,
  zh-1563bd74 88.1 -> 99.2 (Word's 29 pages, the footer box T16 noted
  among them), checkboxes 66.7 -> 100; nothing down. (No `w:between`
  line yet: a group that names one would draw it between.)
  bug65649 67.8% -> 79.0; nothing else moved (clean A/B, n201 vs n200).
- **A list number takes its level's own size (2026-10-15).** A level's
  `w:sz` sets its number, and a number larger than the text makes the
  first line as tall as a line of that size. bug65649's "3.1.1." is 14pt
  over 12pt text, and its first lines stand 15.9pt under the line above
  in Word's print where the others stand 13.8. Ours drew the number at
  the text's size and the lines uniform. The line's height arrives by
  the zero-width space the Symbol bullets already use (a placeholder box
  sets no height). bug65649 96.4 -> 99.7; nothing else moved.
- **A Latin line's baseline is its tallest run's (2026-10-15).** The
  baseline was the first run's alone. Word sets it under the tallest
  run on the first line, and a larger size or a Symbol box lowers it.
  form_footnotes' "D - " box after 11pt spaces sets "Concessão" 0.96pt
  under the 10pt "F - Validade" beside it in Word's print. Ours set the
  two level, and they now stand 0.96 apart. Not for East Asian lines,
  whose lead stretch already decides, nor for stated line heights. No
  score moved: form_footnotes' extra page comes from its rows, each
  about 0.4pt short. Word starts a cell's text under the whole of the
  row's top border, and ours starts it at the border's centre.
- **A row's own borders rule its cells (2026-10-15).** A row's
  `w:tblPrEx` borders stand for every side its cells leave unstated:
  its top and bottom from the exception's top, bottom or insideH by
  where the row stands, and its sides likewise. form_footnotes' last
  table rules only its rim, and every row's exception rules the lines
  between them. Ours read the exceptions for saving alone, so the
  rows had no inner rules and no room for them, and the "H -
  Observações" row stayed on page 1 above the footnote. The sides go
  to layout only (`rowBordersXML`), and a save writes the row's
  exception back as before. form_footnotes 48.3 -> 90.8; nothing else
  moved (the Chinese files' exceptions repeat their tables').
- **Separated cells hold both their side lines (2026-10-15).** In a
  table with cell spacing each cell's lines lie inside its own box, so
  its text loses the whole of its left and right line widths. Ours took
  a collapsed table's share, half a line on the right and none past the
  first half on the left. bib-chernigovka's 51pt year column of outset
  lines held "90 лет" on one line in ours, where Word's print wraps it
  and every row of the calendar stands a line taller. bib-chernigovka
  90.3 -> 99.6; nothing else moved.
- **A group of text boxes is read whole (2026-10-15).** A drawing
  group (`wpg:wgp`) of text boxes one above another, all as wide as the
  group, now gives every box's text. Each later box's text is set from
  its own place in the group, or up from its foot where it is anchored
  there (`RichTextBox.parts`). 60316's résumé sidebar is a name box over
  an address box anchored at its foot, and only the first was read.
  Found on the way: a paragraph carrying a floating object clipped its
  painting 10,000 pixels above and below, meant as unbounded. At the
  PDF's 20 pixels a point that is 500pt, which cut off the foot of a
  page-tall box. 60316 81.8 -> 97.0; nothing else moved. Groups whose
  boxes stand side by side or differ in width are left as before
  (shapes-with-text).
- **An embedded object shows its metafile (2026-10-15).** An embedded
  object (`w:object`: an attached file, a sheet, a document) is drawn by
  the WMF or EMF its `v:imagedata` names, played by Slides' metafile
  player (`WriterMetafiles`, through `RichLayout.objectPainter`, which it
  now shares with `WriterCharts`). Writer drew no metafile at all, so
  these printed as grey boxes or nothing. tika-3388's attachment icon
  and caption, "約翰的測試文件 .msg", is a whole page. Its EMF splits a
  surrogate pair over two text records, and the halves decoded as
  replacement marks that Word does not draw. They are now dropped.
  The bitmaps a metafile carries, such as an attachment's icon, are not
  drawn yet. tika-3388 0 -> 100, EmbeddedDocument 50 -> 100,
  WordWithAttachments 0 -> 2.6 (Word printed it with its comment
  balloons); nothing down. Five documents carry metafiles.
- **A VML picture is drawn (2026-10-15).** A picture written in VML
  (`w:pict` with a `v:imagedata` of a PNG, JPEG, GIF or BMP) went the
  kept-object way with no bytes, and printed as nothing. It now carries
  its picture. zh-64044a1d's nine charts and photos stand where Word's
  print has them (page 15: 90,78-510,375 to Word's 90,77-510,374). Their
  room was already kept, so no score moved.
- **A chart's numeric categories are shown in their format
  (2026-10-15).** A category cache of numbers with a format code (most
  often a date) is shown in that format, or in the axis' own format
  where it is not linked to the source. chartex's radar and box charts
  have days 37261 to 37265 in an m/d/yyyy cache. Word prints 1/5/2002 to
  1/9/2002, and ours printed the serial numbers. Shared with Slides,
  where no deck of the 3,347 in the PowerPoint corpora has such a cache.
  chartex 33.8 -> 35.2; nothing else moved.
- **A kept heading needs only the first lines of a row that may part
  (2026-10-15).** A paragraph kept with the next, followed by a table,
  asked for the table's whole first row. Word asks only for the row's
  first line in each cell, unless the row may not part, and then parts
  the row at the foot. zh-64044a1d's "附件五" heading stands at page
  88's foot in Word's print, with the first two lines of its form's
  five-line title row. Ours sent heading and form to page 89, and the
  next four pages ran a form late. zh-64044a1d 91.1 -> 93.7; nothing
  else moved.
- **A body frame on the page stands at its height (2026-10-16).** A
  framed paragraph in the body whose frame is anchored to the page is
  set at the y it states, and the flow goes on from where it stood, so
  a frame takes no room. A run of paragraphs with one frame is one
  frame. The frame is as wide as it says and, anchored to the page, at
  its x. A frame that names no vertical anchor counts as on the page.
  An x stated in the style chain wins over an alignment from further
  down it, since the cover's "实施" date has its own style's x and its
  parent's right alignment, and Word prints it at the x. zh-90e0cea8's
  standard cover is all frames, and set in the flow its dates stood
  168pt above Word's and its title parted. Now the dates, the title and
  "山东省地方标准" stand within 3pt of Word's. The "发布" frame, whose
  style chain anchors it to the margin, is still not where Word prints
  it. zh-90e0cea8 92.3 -> 93.8; nothing else moved (a peer's commit
  moved zh-9c5d0c3f at the same time).
- **Text ruled round takes the automatic space twice where widths are
  balanced (2026-10-16).** Labs `ap1`–`ap4` (zh-06c46ba9's package,
  Word 16) set its boxed "範例1" (`w:bdr` on the runs, 14pt) with "例"
  and "1" 21.1pt apart, 17.5 without the border, and 17.5 without
  `w:balanceSingleByteDoubleByteWidth`. So an ideograph and a Latin
  character are a half em apart inside a bordered run, twice the
  balanced quarter. Ours gave the quarter, and every reference example's
  first line took the character Word wraps ("…之政策合作"), which pushed
  pages 52 to 55 a line on. zh-06c46ba9 87.9 -> 92.6; nothing else
  moved. The border's own 0.5pt after "1", and the 0.2 over the next
  space, are not built.
- **A raised mark that opens its line is drawn before it (2026-10-16).**
  Raised and lowered runs are painted in a pass of their own over the
  line, where they stood unseen, so a PDF held them after the line's
  text. A note's own mark opens its line ("i Endnote", "1 Footnote_sdt"),
  so text readers and copying gave "Endnote i", and the scorer matched
  neither line. Word's print holds the mark first. Marks that open their
  line are now painted before it and the rest after. A mark inside a
  line still comes after its line's text, where Word's print has it in
  place. endnotes 92.9 -> 100, Bug54849 91.3 -> 100; nothing down.
- **Raised and lowered runs are drawn in their line (2026-10-16, T48).**
  The engine has a baseline shift now: skparagraph's
  `TextStyle::setBaselineShift`, through `txt::TextStyle::baseline_shift`
  and the bridge's `SetBaselineShift` (starling-engine 71811aeb), as
  `TextStyle.baselineShift` in Swift. Under Word's rules a superscript
  is set in its line at 0.355 of its full size up, a subscript a fifth
  down, where it used to stand unseen and be drawn again over the line
  (`_paintScripts`, still the web's way: skwasm has no setter,
  `NativeParagraphBuilder.supportsBaselineShift`). A PDF then holds a
  mark inside a line where it stands, and Bug54849's line reads
  "Blahdeblah11" as Word's does. A shifted run is given a hair of a line
  height and kept out of the strut: counted whole, its raised ascent
  made every line with a note mark taller than Word's (bug59058 99.9 ->
  62.1, bug65649 99.9 -> 92.8). Marks stand where the overlay put them,
  to 0.03pt. zh-06c46ba9 92.6 -> 93.9; nothing down.
- **A paragraph's trailing spaces take no line height (2026-10-16).**
  8c5c457e sets the spaces that end a paragraph after ideographs in the
  ideographs' face. On the Mac a space there still resolves to another
  font than the ideographs do, and that font's 4.4pt descent made
  zh-1563bd74's footer line 19.0pt where the ideographs alone make 18.2.
  The page lost a line and the document ran to 30 pages, against Word's
  29. Word's lab `hfl` gives trailing spaces no height at all, so such a
  space now has a hair of a line height and no part in the strut, as a
  shifted mark has. zh-1563bd74 88.6 -> 99.7 with Word's 29 pages;
  nothing down.
- **A side a cell leaves bare is ruled by its neighbour's line
  (2026-10-16).** Two cells share a vertical edge. Where one says nil for
  its side and the other draws a line there, the line stands on the edge,
  and Word keeps the first cell's text clear of it as of its own line.
  zh-37b6536f's count cells say nil on the left under a 1pt line from
  the cell before. Word sets "尚未审结" and "总计" a character a line in
  their 30pt, where ours, counting no line on that side, took two. A
  cell's side with no line of its own now takes its neighbour's.
  zh-37b6536f 96.2 -> 97.7; nothing else moved.
- **A balanced half-width space takes half the grid's addition, not twice
  it (2026-10-16).** Where single- and double-byte widths are balanced, a
  space is half an em and the run's spacing twice (lab `sp`, 8.31pt at
  16pt spaced 0.15). The spacing the style holds includes the character
  grid's addition, and that went twice too. zh-f0bd9ea8's two spaces
  after "第一条", 16pt on a grid of -0.21, are 7.9pt apiece natural in
  Word's print (8.13 justified, the ideographs 15.79 + 0.24) and were
  7.6 here. Now the grid's share is half. zh-64044a1d 96.7 -> 97.1,
  zh-6d1afa56 97.8 -> 98.3; nothing down.
- **Before 2013's layout, a Latin word at a body line's end is taken
  wherever the marks and spaces can give (2026-10-16).** Lab `dg`
  (Word 16, zh-2a241df1's package, mode 14, justified 14pt
  仿宋_GB2312): "季度，杭州…举报43.5" takes "43.5" up to a need of 8.1pt and
  not 9.1. The comma gives its whole half, 7pt, then half the 3.56pt
  space before the digits. With no full-width mark on the line it is
  not taken even at 2.1. Ours capped such a word at half the character
  before it (7pt, after 报), which holds for an ideograph but not for a
  word. Two limits stand. A word that starts past the margin is not
  taken: zh-9dd9ce6d's "…次年" leaves its "3", whose space before it is
  already over the line. And none of this applies on a character grid:
  zh-d68ac84a's "给予50", 11pt over with 12.8 to give, stays a line
  down, and that grid's rule is not measured. zh-2a241df1 9.5 -> 35.2
  and zh-8112041b 69.4 -> 70.8 in the second sample; zh-1563bd74
  99.7 -> 100 and zh-06c46ba9 94.8 -> 94.9 in the first; nothing down.
- **A column chart's line on a second value axis is drawn
  (2026-10-16).** zh-2a241df1 (second sample) charts its complaint
  counts as columns, with their year-on-year shares as a line on a
  percentage axis at the right, `c:valAx` `axPos="r"`. A combination
  was read only where both kinds share one pair of axes, so both charts
  printed as empty boxes. The line's own value axis is now read (its
  format, bounds, step, deletion). The line is scaled by it, and its
  labels ("60.00%") stand at the plot's right, which gives up their
  room. zh-2a241df1 went from 7.6% to 9.5%; nothing else moved. Left:
  Word's charts there carry a data table (`c:dTable`) under the plot,
  which this app does not draw. Excel's left axis runs 0 to 500,000 by
  50,000, where our nice-step rule (×1.05, nine intervals) gives
  100,000. That rule is Slides', and PowerPoint's prints set it, so it
  is left alone here.
- **A no-break space takes its width, and the hAnsi face's past ASCII
  (2026-10-16).** zh-17749c13 is from a second Word sample: 20
  unprinted documents of the zh corpus, prints in
  `~/starling-word-check/zh2`, scored with `DOCX_WORD_REFS`. It spaces
  its "第十三条" and "（一）" openings with U+00A0. In Word's print each is
  an em of SimSun, whether the run's ASCII face is 宋体 or 仿宋_GB2312
  with `w:hAnsi` 宋体. Ours had two faults. The em the square face's
  table gives a no-break space (lab `nb1`) was set as spacing on the
  space itself, and the engine sets no spacing on a space: it came out
  at the stand-in's 0.29 em. And the width was the ASCII face's, where
  Word takes the `w:hAnsi` face for Latin characters past ASCII. Now
  the width rides on a word joiner after the space, and past ASCII the
  hAnsi face's own advance is taken where it has one. zh-17749c13 went
  from 7.9% to 85.6% in the new sample; nothing moved in the checked-in
  corpora.
- **A frame on the margin stands at its y, centred where it says; a
  run's 100% scale undoes its style's (2026-10-16).** zh-90e0cea8's
  cover ends with "山东省市场监督管理局 发布" in a frame. Its style's base
  (发布部门) anchors that frame to the margin and centres it, 372pt
  wide, and the paragraph's own framePr gives y 751pt. Body frames were
  placed at their y only when anchored to the page, so this one stood
  in the flow at the page's head, 618pt above Word's. Its runs say
  `w:w="100"` over the style's 135, and 100 was read as no scale at
  all, so the style's 135 stood and the line ran 35% wide. Now a
  margin-anchored frame is set at its y under the top margin, centred
  between the margins where its chain says `xAlign="center"` and gives
  no x, and `w:w="100"` is a scale of its own. The line stands at
  Word's x and 3pt under Word's baseline. No score moved; the 3pt is
  the scorer's limit. Left on the cover: the "37" of "DB37". Its
  paragraph's own framePr (`w:w="0"`, `wrap="auto"`, `yAlign="inline"`)
  over its style's margin frame is ignored in Word's print, where the
  style's frame (x 337pt, y 8.6pt) places it. Ours keeps it in the
  flow.
- **A floating text box's text is on the document's line grid
  (2026-10-16).** zh-454e2e29's diagonal header cell labels its corners
  "人數", "官等" and "類別" with 12pt 標楷體 text boxes (wrapNone,
  anchored in the cell's paragraph). In Word's print each stands two
  18pt pitches deep, centred in them, as body text on that grid does.
  Ours set the box text on its own line, 8pt higher. A floating box's
  text now takes the grid. Text set two lines in one (`w:combine`)
  stays off it: it is a box in the line, and on the grid its row grew
  a pitch. The labels are within 0.4pt of Word's now. No score moved,
  since the line match groups those cell lines alike either way.
  (Linux, the same day, built at the same time and merged into this:
  every box but `w:combine`'s, floating or inline, and the grid of the
  section its anchor stands in, not the document's — zh-6cd1befe's flow
  chart stands in a section of no grid, and on the last section's its
  22pt title went 4pt low. On Linux zh-454e2e29 94.8 -> 96.7%; nothing
  else moved.)
- **After a space, a character is taken wherever the marks can give
  (2026-10-16).** Before Word 2013's layout a justified line takes a
  character over its end by no more than half the one before it.
  After a space no such half applies: the character is taken wherever
  the line's marks can give what it needs. Taiwan's centred "，。、"
  give nothing toward it. Lab `sp` (Word 16, zh-06c46ba9's package,
  mode 14, justified 14pt) tested "（drug abuse）之機制建構，2007 年".
  Word takes "年" 14pt over and not 15, the two brackets' halves. As
  "2007年" it leaves it from 5 over, the "7"'s half. With no full-width
  mark on the line it takes it up to about half its own em, as before.
  zh-06c46ba9 p55 had sent "年" and then the URL down a line.
  zh-06c46ba9 94.3 -> 94.8; nothing else moved.
- **A line holding a compatibility ideograph has Noto's line over and
  under the baseline (2026-10-16).** Word on a Mac sets a few CJK
  compatibility ideographs (狀 U+F9FA, 行 U+FA08, …) in Noto Sans SC.
  Its line then stands 1.4pt further under the line above at 12pt and
  0.5 deeper (lab `cj2`). Ours gave the line Noto's height through a
  word joiner. The joiner's glyph comes from whatever face has one
  (Caladea on the Mac), and the engine shares a height out by that
  face's ascent and descent. Each such line stood 2.6pt under the line
  above and no deeper. The joiner is now sized and set at an even
  share, so its ascent and descent are Noto's less the ideographs'
  face's, added to that face's measured line. At an even share the
  size fixes ascent less descent, and the height sets the rest.
  zh-8e8d4c40 90.4 -> 98.9; nothing else moved.
  (2026-10-17) That joiner kept the line from parting before the
  character, since a word joiner forbids a break on both sides.
  zh-5b7ae054 (121 compatibility ideographs) ends a line at "…抗災能" in
  Word's print, with "力" U+F98A opening the next. Ours carried "能力"
  over, and every line of the paragraph after it ran a character early:
  with the file's own "力" swapped for U+529B, ours fit "能". A
  zero-width space now goes before the joiner, after an ideograph that
  is not an opening mark: the line may part there, and the joiner goes
  on with the character. zh-5b7ae054 64.7 -> 98.0, zh-8e8d4c40 98.9 ->
  99.4; nothing fell of the 279 files holding any (one base).
- **YaHei's em dash is 1.08 em (2026-10-18).** The faces Word on a Mac
  sets in YaHei draw "—" at YaHei's own 1.0801 em, regular and bold
  (msyh.ttc, msyhbd.ttc). The Latin stand-in's dash is an em. zh-8d6f702e's
  "160—230" sets it 17.18pt at 16pt on its grid of -0.21 in Word's print,
  ours 15.79, and the line then took "累", which Word wraps. It is now
  in YaHei's table of widths beside its ellipsis. zh-5a9a85c6 98.7 ->
  100, zh-8d6f702e 88.2 -> 88.4; nothing fell of the 186 (one base).
  Left in zh-8d6f702e: on that line Word also squeezes nothing, while
  ours took "（", "）" and "，" in by 2.63 apiece to fit "累". On
  p23's "…150毫米，或全" it is the other way round: Word gives "：" and
  "，" 3.94 apiece (a quarter em) to take "全", and ours squeezes
  nothing. (Mode 12, compressPunctuation, a -0.21 grid.)
- **Under `w:wordWrap` off a paragraph's closing spaces wrap (2026-10-18).**
  zh-621d8756's forms end paragraphs in runs of underlined spaces. In
  Word's print they fill the lines up to the margin, one space over it,
  and go on to the next line: "陈述申辩人：（…）" and its spaces take two
  lines, "答：" and its spaces five (Word for Windows prints pages 21-27
  the same). Ours hung them all past the margin on the text's line, and
  every page from p21 ran a line or two short. The closing spaces of
  such a paragraph now have a break after each but the last, and the
  engine hangs a space only where a line ends on it. Not where the
  paragraph is set right or centred: zh-c5b5087b's and zh-1563bd74's
  footers, "X…人民政府发布" and five spaces set right under indents wider
  than the line, keep one line in Word's print, and wrapping them cost
  each page a body line. zh-621d8756 84.2 -> 95.5; nothing else of the
  18 files with such paragraphs moved (one base). Left: Word also
  squeezes a "：" before the spaces to take one more on the line (11.6
  or 10.8 where it is 15.6), so its "答：" lines hold a space more.
- **Autofit counts a Latin word as parted where `w:wordWrap` off parts it
  (2026-10-18).** zh-f2441f00's HTML-style tables (100% wide, auto cells,
  no side margins) keep their grid in Word's print: p17's columns are
  its 1636/1635/715/5391/844 twips to the tenth. Ours widened the last
  to 44.5pt, narrowing the rest, because its narrowest-content measure
  took "(iCulture)" whole. Word sets that cell "平台(iC" / "ulture)".
  The measure now parts a word wherever the line breaking does under
  wordWrap off. zh-f2441f00 75.2 -> 99.5; nothing else of the 206 moved
  (one base).
- **A text box's text is inset by half its outline, drawn or not
  (2026-10-18).** Lab `c60` (Word for Windows, 60316's package, its
  "Allison" text box: insets 0, an outline with no fill) moves the text
  down and right by 0.24pt for the box's 0.5pt outline, 0.96 for 2pt,
  3.96 for 8pt, and not at all with no width stated. The same 36pt
  exact line set in the body stands 0.24 higher. Each text box's insets
  now take half its `a:ln` width. Nothing in the 330 swept files moved.
  60316's own box is not yet drawn where Word draws it (ours sets its
  text in the body column), so its line does not show it.
- **A character of a `*Chars` indent is as wide as the run's `w:w`
  (2026-10-18).** zh-b24b396a's cover title, 22pt at 135% spaced 1pt
  and centred, inherits Normal's `firstLineChars` 200 (its own
  `w:firstLine` 1280 gives way to it). Lab `b24` (Word for Windows):
  set left, its first line starts 63.4pt in, two of 22 × 1.35 + 2;
  at 100% it starts 48 in. Ours took 48 at 135% too, and the first
  line held "标" that Word sends down. No fake-bold spread is in it.
  zh-6b4b9397 97.3 -> 100; nothing else of the 330 moved (zh-b24b396a's
  title is right now; the line match paired its lines before too).
- **A text box's text can run turned a quarter (2026-10-18).** A box's
  `wps:bodyPr vert="vert270"` reads its text up from the box's foot,
  its lines stacking rightwards from its left; `vert` reads down from
  its top. Either way the lines are as long as the box is tall.
  zh-b24b396a's drawing labels "20", "36", "30" and "297" are
  vert270 boxes 10.5pt wide and 21 tall. Ours laid them across, so
  "297" wrapped in the 10.5pt and each stood about 14pt off. Now they
  stand within 0.3pt of Word's print and read upward as Word's do.
  zh-b24b396a 86.0 -> 91.3; nothing else of the 350 moved. Left there:
  six 7.8pt-long vert270 boxes of "30" that Word wraps and shows as
  "0" (ours fits both digits, 7.6pt), and a few 12pt "A"/"B"/"C"
  labels ours draws that Word's print does not.
- **A triangle or star in a face Word lacks is SimSun's, line and all
  (2026-10-16).** Word on a Mac sets a Chinese face it does not have
  (仿宋_GB2312, the 方正 faces, 標楷體) in Microsoft YaHei. Its prints
  draw ▲ and ★ from SimSun even so, and measure their line by SimSun.
  Lab `tr2`, rows of one 12pt 仿宋_GB2312 "▲" on zh-6cd1befe's 15.6pt
  grid: Word sets the line one pitch tall, so a row is its space before
  plus 16.2, or 19.2 at least. YaHei's 1.715-em line took two pitches in
  ours, 31.9, and its task table's rows with 8pt of space before stood
  5pt taller than Word's. ○ and □ stay YaHei's, as in zh-7dc3afad's
  print, and taking them too cost that document 1.6. Only under
  `OFFICE_WORD_FONTS=mac`, through `RichResolvedFace.symbolFamily` on
  the YaHei stand-in. zh-6cd1befe 96.4 -> 97.8; nothing else moved.
- **A tab on a wrapped line goes to the stop after where its own line
  has got to (2026-10-15).** The tabs were measured along the paragraph
  laid out on one line, so a tab on a second or third line went to the
  stop after where it would have stood unwrapped. bug65649's cell
  "…кнопка выхода<tab> ST-EX011SM, Замок электромагнитный<tab>
  VIZIT-ML400M-40)" has its tabs at 241.0 and 276.4 in Word's print —
  default stops 35.4pt apart from the cell's edge — and ours at 227.0
  and 284.5, so "40)" took a line of its own. The measure-again-on-the-
  wrapped-lines pass that PowerPoint's tabs had (HowWeRefactor) now
  runs for Word's too. bug65649 79.0% -> 83.8; nothing else moved
  (clean A/B, n203 vs n202).
- **A file's embedded East Asian faces are drawn (2026-10-15, T8).**
  `w:embedRegular` (or `w:embedBold`) names a part under `word/fonts/`
  whose first 32 bytes are XORed with the `w:fontKey` GUID, read as 16
  bytes from its last hex pair to its first (ECMA-376 part 1, 17.8.1).
  Word for Mac draws those faces — zh-e37f8d40's print is in the
  FangSong_GB2312, SimHei, KaiTi_GB2312 and FangSong it carries — and
  ours drew PingFang for all of them. The importer now loads each
  embedded East Asian face (`OfficeFonts.loadEmbedded`) under a family
  named by its bytes, because a file saves a subset (that 仿宋_GB2312
  holds 656 characters, its 楷体_GB2312 22) and two files' subsets
  under one name would mix; the resolver draws an East Asian run in it,
  and what the subset lacks falls back as before. The measure is
  unchanged: an embedded name keeps the square model it already had
  (`isEmbedded`). The Latin faces a file embeds (saut_page's Times and
  Arial) are left to the clones, which match Word's to the unit.
  zh-e37f8d40 94.0% -> 96.6 (the text layer groups as Word's now);
  nothing else moved.
- **Exported PDFs read 人民, not ⼈⺠ (2026-10-15, starling-engine
  a0cbed78).** A CJK face often draws a radical and its ideograph with
  one glyph, and Skia's ToUnicode keeps the lowest code point for a
  glyph, so text copied or searched in our PDFs came back as Kangxi or
  supplement radicals — every Chinese document, by the hundreds.
  `WritePdf` now gives the text runs holding such glyphs their UTF-8
  with the ideograph (Unicode's EquivalentUnifiedIdeograph table) and
  Skia writes those glyphs as ActualText. The line match had forgiven
  radicals all along, so no score moved for it; PyMuPDF and PDFKit now
  both read the real characters.
  One radical slipped through (2026-10-16, starling-engine af73bfda):
  a Simplified face draws ⼾ (U+2F3E) with its 户, while the table pairs
  ⼾ with 戶, which such a face draws apart — so 户 still read back as
  ⼾, 206 times in 19 documents. A glyph that reads as a radical after
  the table now takes the lowest unified ideograph that reaches it. The
  sweep's text moved only there; four documents gained up to 0.4 (the
  line match had been missing those lines).
- **A no-break space is an em in a square face (2026-10-15).** Lab
  `nb1`: "甲" + ten U+00A0 + "乙" at 12pt sets each no-break space 12pt
  in 宋体, 黑体, 楷体 and 仿宋, where a space (U+0020) is 6pt; in a run
  whose Latin face is Times it is Times' 3pt, and YaHei keeps its own
  3.55. It goes by the run's Latin face whatever the hint. Chinese forms
  space their "年  月  日" lines with them. The square faces' Latin side
  now sets U+00A0 at an em (`otherAdvances`). No document moved by 0.3.
- **Autofit tables: what makes Word re-fit one (2026-10-15, T1; labs
  `at1`–`at5`, bodies 56–60, in ~/starling-word-check/lab).**
  zh-0aac9d1a's forms are autofit, tblW 8578, grid 1350/3022/1526/2680,
  cell margins 105; Word prints them 34.6/187.5/110.6/156.4pt, 489pt in
  all. What the labs found: (1) Word keeps the saved grid exactly, as a
  fixed table, until a cell's narrowest unbreakable content plus its
  margins is wider than the grid columns it covers — a cell's longest
  word growing, or ordinary breakable text, changes nothing. (2) Then
  that cell gets exactly its unbreakable width, and the other columns
  give way down to their own narrowest content (a column of "相关证明材料"
  to 22.6pt: one character and the margins; "列入“红" holds an opening
  quote to its character, so 34.6). (3) The table is the stated width
  while that suffices, and wider when the minimums need it (a 3-column
  span of 50, 55, 62, 70 Courier "W"s: 428.8, 429.1, 479.5, 537.1pt).
  How a spanning cell's width is shared among its columns is NOT
  proportional to the grid and was not found. In zh-0aac9d1a the cell
  that triggers it is the stamp row's line of no-break and ordinary
  spaces, which Word holds whole up to "（盖章）" (444pt) — it does not
  break at those spaces, for a reason not found (no compat switch
  explains it); a line of breakable words in the same place does not
  trigger the re-fit. So nothing is built yet: a min-width model
  without that break rule changes nothing in the one measured
  document.
  Correction (lab `sp1`, 2026-10-15): Word DOES break that stamp line
  at its spaces — in a 120pt cell it wraps over five lines, as ours
  does — so the re-fit is not about a minimum width at all. What fits
  every lab so far: an autofit cell grows toward its unwrapped (max-
  content) width up to a cap, wraps its text there, and the column then
  shrinks to the widest wrapped line — the stamp line's 540pt wraps
  before "（盖章）" and leaves 444, the width Word gives the span (plus
  margins, 454.5). The cap lies between 477 and 525pt of table; what
  sets it is the next lab (vary the page's text width and margins).
  Then (labs `cap1800/1000/2600`, `caplong`, `sp2`): there is no cap —
  the page's margins change nothing, and 16 more no-break spaces widen
  the span by exactly their 192pt. Word's AUTOFIT MEASURE treats a run
  of ordinary spaces that follows a no-break space as joined to both
  neighbours: "nbsp×30 + 26 spaces + 年" sizes the cell as one 528pt
  piece, "(年 nbsp nbsp 3 spaces)×12" as one 630pt piece, while spaces
  between ideographs or Latin words part as ever. Its LINE BREAKING does
  not (lab `sp1`: in a 120pt cell the stamp line wraps at those
  spaces) — tried as a line-break rule, it made ours part "（盖|章）"
  instead, reverted. So T1 needs its own min-content measure (a cell's
  longest piece under that rule, plus margins and indents), then the
  rule above: that cell exactly that wide, the rest down to their own
  minimum, the table no narrower than its stated width.
  Built (Linux session, 2026-10-15; `_autofit` and `_minContent` in
  RichLayout, `STARLING_RICHTEXT_AUTOFIT=1` traces it). Of zh-0aac9d1a's
  four forms Word re-fits only the first, and the rule says why without
  another lab: that form's stamp line is in 仿宋, a face Word has, whose
  no-break space is an em, so its joined piece "nbsp×14 + 26 spaces +
  年  月  日" is 444pt against 350.9 of room; the other three are in
  仿宋_GB2312, set in YaHei, whose no-break space is narrow, and their
  pieces fit their grids. A cell's narrowest setting is measured as our
  own line fitting parts its text (`_glued`, `_span`'s breaks, after a
  run of spaces, at a line break), each piece as wide as the paragraph
  sets it, plus its margins and its side indents — negative ones too:
  bug65649's equipment table indents every paragraph -113 twips a side,
  and without them its "№ п/п" column re-fitted for "(согласно" that
  Word's print holds in 54pt. (Not the engine's minimum intrinsic
  width: skparagraph's fast path for a one-run paragraph that fits
  never parts it, so a line of ideographs measured as all of them.) A
  cell must be over by a point before the table re-fits — four
  documents had cells a tenth to 0.75pt over their grid that Word sets
  as saved (bug57031's HTML tables, saved at Word's own fit of their
  widest words, measure 0.6–0.75pt over it in ours). A
  column whose every cell spans keeps its width. Line match (Linux):
  zh-0aac9d1a 63.3% -> 100% (12 pages, as Word's); nothing else moved.
  Still open: how Word shares a span among its columns. Ours gives
  each its own narrowest and the rest as the grid shares it,
  34.5/183.0/109.5/163.5pt against Word's 34.6/187.6/110.5/156.4 —
  close enough that no line moves here, but a lab is needed (a span
  over three columns of unequal content and grid, its narrowest
  varied) before another document depends on it.
- **All-auto tables: Word fits them to their content (2026-10-23;
  Windows 01QbbApP, labs `aa`, `ab`, `ac` in ~/starling-doc-check/lab, on
  Word for Windows; zh-e49d7943 p16, handed over by Linux 017F2GnT).**
  The rule above (keep the grid until a cell can't fit) holds for tables
  whose cells state widths. A table with `tblW` auto where EVERY `tcW` is
  auto is a different case: Word ignores the saved grid and fits the
  columns to their content, like HTML's auto layout. Lab `aa` is
  zh-e49d7943's calendar alone. As saved (all auto) Word prints it
  69.1/57.6/63.0/62.9/62.9/71.9 inside. With each cell's `tcW` set to its
  grid width it prints the grid, 67.6/60.3/63.5/63.6/63.5/70.1. The fit,
  from labs `ab` and `ac` (Courier New 10pt, every width exact):
  (1) Each column has a min and a max: the widest of its one-column
  cells' narrowest settings and of their unwrapped paragraphs, each with
  the cell's margins. The max includes Word's automatic gap between
  digits and ideographs: 0.26em, so "11初四" is 18.6 + 4.2 + 32 at 16pt.
  (2) Spans, narrowest first: where a span's max is over its columns'
  sum, the excess goes to them in proportion to their maxes. The same
  goes for its min against their mins. Lab `ac` s1: 'a' / 5 W / 10 W
  over a 109-character span prints 64.6/156.6/271.6, and this gives
  64.5/156.6/271.8. s2 spreads the span's min the same way.
  (3) If the maxes sum to no more than the room (the column's width plus
  the cell margins either side: 492.8 for 481.9), the columns are their
  maxes and the table is that narrow. Lab `ab` v3 prints 22.8/76.9/46.8
  for 'ab' / 11 chars / 6 chars, whatever the grid says. Otherwise the
  table is the room wide and each column is min + (max − min)·k, with k
  the same for all. v1 prints 213.2/118.6/161.1 (this gives
  213.3/118.5/161.0); v4 prints 406.4/16.9/69.5 (this gives
  406.4/16.8/69.5); v2 is v1 with a 50% wider grid and prints the same.
  On the calendar, with YaHei's metrics standing in for 標楷體 (as Word
  sets it there), this gives 35.9/69.2/57.6/62.9/62.9/62.9/72.0/69.2.
  That is columns 2–8 within 0.1pt, the first about 0.4 under.
  "星期二" then wraps "星期" / "二" as Word's does.
  Not tested: mins summing past the room, merged-down cells, nested
  tables, and lab `ac` s7, which is off by 0.7pt on a 2165pt span.
  Five corpus documents have such a table: zh-e49d7943, zh-12f87285,
  bib-chernigovka, bug57031 and drawing.
  Lab `ae` adds a cap. A cell's max counts as 1580pt at most, about
  Word's 22-inch limit on a table. With the first cell's words at 800,
  1200 or 1500pt, this rule matches Word to 0.1pt. At 1720, 1985 or
  2975pt Word sets the table exactly as at 1580.
  zh-12f87285 (WPS's save; 194 rows of 14pt YaHei, some descriptions
  4400pt unwrapped) is fitted all the same: cut to 12, 16, 20, 30, 50
  or 100 rows (lab `ad`), Word gives each cut its own widths. The full
  table's fit is simply the grid WPS saved. Without the cap ours gave
  23.2/38.6/54.8/280 for 30.4/47.7/84.5/234.3 (100 -> 8.5). With it,
  30.5/47.7/84.6/234.0, but the description column 0.3pt narrower still
  re-wrapped lines Word keeps whole (100 -> 88.5). So, as for the rule
  above, a fit within a point of the grid in every column keeps the
  grid.
  Built (`TableStyle.contentFit`, `_autofit`, `_maxContent`).
  zh-e49d7943 86.6 -> 93.5 (its p16 now matches; it was 1 line); the
  other four are unchanged (pair aa-base/aa-new3).
- **Vertical writing in a cell (2026-10-15, T20; Linux, no lab).**
  Word's `w:textDirection` tbRl, tbRlV and tbLrV all print the same way
  in zh-2b955411: the ideographs upright, stacked down the cell one
  advance apart (9pt at 9pt), placed along the cell by the paragraph's
  alignment — "评估目的" centred in its 58.6pt row (Normal is `jc`
  center), "经济行为类型" under `jc` distribute first at the top and
  last at the bottom, (77.3 − 9.1) / 5 = 13.64pt apart. The reader
  turned tbRl and tbRlV a quarter, every glyph sideways, and read tbLrV
  as across: three lines of two characters made its row 6.7pt taller
  than Word's, and the 282pt stamp row after it went to the next page.
  Now all three read as `.down` with `uprightIdeographs`; a paragraph of
  East Asian characters in such a cell is drawn a character at a time,
  each turned back upright in its box on the turned line, its em square
  (0.88 over the baseline, 0.12 under) centred there rather than its
  line, which a 28pt exact line makes far taller than the character.
  A paragraph with Latin letters is still drawn turned whole — Word turns
  those letters too, but its ideographs would stand, which is not built.
  The value as written is kept for the save. Line match: zh-2b955411
  89.7% -> 98.0%; nothing else moved.
- **Distributed paragraphs (`w:jc` distribute, 2026-10-15; Linux, from
  Word's prints).** Word spreads the last line too: its first
  character at the line's start, its last ending at the line's end, the
  room left shared evenly between every two characters, Latin
  parentheses among them — "適用考試名稱" 57.22pt apart across a 309pt
  cell, "總計" one at each side, "(所屬機關名稱)" 17.26 apart, a cover's
  "山东省地方标准" across the page (zh-a7728bc9, zh-454e2e29, zh-90e0cea8,
  each within 0.4pt now). The share is a word joiner before each
  character as wide as it (`_span`'s `spread`): letter spacing on the
  character itself is set half before it and moved the line's first a
  half share in. The line is set a twentieth of a point short of its
  end, or a point: to the hair, the engine's rounding put zh-454e2e29's
  ")" on a line of its own. (The joiners come out of an exported PDF's
  text as spaces, as the quotes' blanks do.) No line moves for it — 33
  paragraphs in seven documents, each already on Word's lines — so the
  line match is unchanged; it is the pixels.
- **A paragraph's compound border takes all its lines' room
  (2026-10-15; Linux, from Word's print).** zh-69bbcc3c's red letterhead
  rule, `w:pBdr` bottom thinThickSmallGap at 2.25pt, is a 2.16pt line by
  the text, a 0.72 gap and a 0.72 line in Word's print, 3.6 in all; ours
  reserved the width alone and drew one line, and the page under it
  stood 1.14pt high. Paragraph borders now take `_ruleRoom`, as cells'
  rules do, and draw a compound line as its lines (`_ruleLines`: the
  thick by the text for thinThick, outside for thickThin, a double's two
  a width apart). zh-69bbcc3c 98.1% -> 99.5%; nothing else moved. A
  table's compound rules are still drawn as one line.
- **A cell merged into a row rules it by its continuation's top line
  (2026-10-15; Linux, from Word's print).** zh-ae655121's balance sheet
  heads three cells merged over its first two rows, and each
  continuation (`w:vMerge` without restart) states a double line on top
  — never drawn, the cell running on through it. Word's second row, 37.6pt
  "at least", stands 37.6 + 2.25 tall between its lines all the same:
  the double line's room, where the row's own two cells rule a half-point
  line. Ours took only its own cells' rules, and every row after it
  stood 1.75pt high. A spanning cell's continuation borders now count
  among an "at least" row's rules. zh-ae655121 87.0% -> 94.2%; nothing
  else moved.
- **A header row never parts over a page, repeated or not (2026-10-15;
  Linux, from Word's print).** zh-e37f8d40's application form marks every
  row `w:tblHeader`, so none is repeated (a header of the whole table is
  no header), but Word still parts none of them: its "民政局社会救助股意见"
  row, five lines, goes whole to page 14 where ours parted it three and
  two. zh-e37f8d40 96.7% -> 100%; nothing else moved.
- **A full-width closing quote closes up like a closing mark (2026-10-16;
  Linux, from Word's print).** zh-15728c84's "线上线下”、“舆情" is set with
  "”" and "、" 5.2 and 5.3pt wide at 10.5pt: the quote gives its blank
  half before a mark as "、" does before "“". Ours kept the quote's em,
  and a cell line left for the next the "涉" Word takes. Across the
  Chinese prints the rule holds wherever punctuation kerns; under
  `w:noPunctuationKerning` (zh-d68ac84a's "”（", zh-69bbcc3c's "”，") the
  quote keeps its em, as the marks do. zh-15728c84 94.0% -> 96.0%,
  zh-e27cd8bf 99.8 -> 100; nothing else moved. What is left of
  zh-15728c84 is a parted row (the board's note under the Mac's leads).
- **On a character grid a line's stretch is its characters as the grid
  sets them (2026-10-16; Linux, from Word's print).** Mode 15's test for
  squeezing a character onto a line compares what the marks must give,
  as a share of their halves, with what the line would stretch by, a
  64th of each character's em. The halves were taken as set, the grid's
  addition with them, and the ems without it: zh-457a8d62 (16pt on a grid
  of 17.0) left "經" 12.44pt over with two marks and 25 characters, which
  Word leaves for the next line and ours took (77.7 against 74.6; with
  the grid both sides, 77.7 against 79.4). zh-457a8d62 97.2% -> 97.3%;
  nothing else moved. Two lines of it still take a character Word does
  not (p47 "…規定：「本法" then "第" 6.6 over, two marks; p52 "…虛報薪資"
  then "之"). Tried: a mark that its neighbour has closed up on (the "」"
  of "。」", the "「" of "：「") gives nothing more — it fixes p47's line
  in the arithmetic but costs seven documents (zh-1a3c7aa0 92.7 -> 82.1,
  zh-6d1afa56 97.4 -> 87.5), so it is not Word's rule.
- **On a character grid an indent in characters counts the grid's
  characters (2026-10-16; Linux, from Word's print).** zh-457a8d62's body
  style says leftChars 200, 16pt text on a grid of 17.0: Word starts its
  lines 34pt in (two grid characters), ours started them at 32 (two
  ems), and every line was 2pt longer than Word's — which is what the
  two lines above came to, not the squeeze test: each took a character
  Word leaves for the next. `_sideIndents` now adds the grid's addition
  to Normal's size, as `firstLineIndent` already did. zh-457a8d62 97.3%
  -> 100%; nothing else moved.
- **YaHei's bold is a taller line (2026-10-16; Linux, from Word's
  prints).** msyhbd is a face of its own: Word sets bold YaHei lines 1.73
  ems apart — 24.21 at 14pt (zh-33aa9899's body, `atLeast` 24, which the
  regular's 24.01 would have met), 27.66 at 16 and 34.62 at 20
  (zh-7dc3afad's contents) — where the regular's are 1.715 at every size
  measured. `RichResolvedFace.boldHeight`/`boldBaseline` (the extra half
  above, half below). zh-33aa9899 96.9% -> 100, zh-4c3793e8 89.5 -> 100,
  zh-7dc3afad 96.2 -> 99.5, zh-8e8d4c40 98.3 -> 98.9, zh-06c46ba9 +0.1;
  zh-799c91cd 96.4 -> 96.0, a knife-edge: its p6 table ends 0.4pt below
  Word's already, 0.7 now, and the empty paragraph after it goes over to
  p7.
- **In a cell a number past its hanging indent has its text straight
  after it (2026-10-16; Linux, from Word's print).** zh-ae655121's notes
  sit in a borderless floating table, list level left 1520 hanging 480,
  "二、" 26pt at 13pt: Word sets "法人提報…" at the number's end and the
  line ends "…應檢附法人審"; ours tabbed to the next default stop, 18pt
  on, and the line ended two characters short. The same document's body
  lists, over their hang the same way, do go to the next stop (tried for
  all paragraphs first: zh-ae655121 94.2 -> 87.0 by its body). No score
  moves — the line match takes a line whose first four characters agree
  — but the breaks are now Word's. Measured in one document only.
- **A row's own cell margins stand over the table's (2026-10-16; Linux,
  from Word's print).** zh-64044a1d's task tables say 28 twips a side in
  `w:tblPr` and 108 in every row's `w:tblPrEx`; Word's print sets the
  duty column's text 5.4pt in from its rule, ours at 1.4, and each line
  held a character more ("…災情查報與協" for Word's "…與"). A cell that
  states no margins now takes its row's exception over the table's (it
  did only where most cells state their own). zh-64044a1d 95.2% -> 95.3,
  bug65649 99.7 -> 99.8; nothing else moved. That page's text still
  stands 3-4pt high: its merged duty cell goes over the page (the
  Windows box's, see the board).
- **A picture is its cell's first line whole, for a kept run (2026-10-16;
  Linux, from Word's print).** zh-64044a1d's flow charts stand alone in a
  one-column table's first row, under "八、參考資料" and two items, all
  kept with the next by heading 1. Word takes the three to the chart's
  page (p68); ours left them at p67's foot, the run's test having
  measured the row's start by its painter's first line — a line, for a
  picture paragraph — where the chart is 418pt. zh-64044a1d 95.3% ->
  95.6%; nothing else moved.
- **A VML picture is set at whole points (2026-10-16; Linux, from
  Word's print).** zh-64044a1d's flow charts (`w:pict`, `v:imagedata`)
  say 410.5 by 396.45pt and 419.85 by 417.95 in their shapes' styles;
  Word draws them 410 by 396 and 420 by 418. On the 18pt grid the first
  then fits 22 pitches exactly (Word's row 396.0), where ours at 396.45
  took a 23rd and set its caption and page 18pt low (p83). Rounded half
  down, as 410.5 is. zh-64044a1d 95.6% -> 95.7, WordWithAttachments 2.6
  -> 5.3; nothing else moved. DrawingML pictures (EMU extents) are
  untouched: not measured.
- **An exact line's baseline needs nothing of the face (2026-10-16;
  Linux).** The 13/16 rule was applied only where the face's own
  baseline was known, and PMingLiU (新細明體) has none: its exact lines
  kept the engine's even leading. The 9pt notes under eight Taiwanese
  reports' tables (16pt exact) stood 1.9pt high, their 12pt cells 0.4.
  Now 12.63pt under the table's rule to Word's 12.72. zh-06c46ba9 78.9%
  -> 79.3; lines over 1.5pt off Word's 668 -> 587, none new.
- **A centred line's picture by the text's line (2026-10-16; Linux).**
  `w:textAlignment` "center" puts the picture's box (effect extent and
  all) with its middle at the middle of the text's line as Word sets
  one: zh-e37f8d40's 16pt 宋体 baseline is 5.73pt (0.358 em) under its
  emblem's middle in Word's print. The engine's middle used the stand-in
  face's ascent and descent and set the letterheads 1.6pt high; they now
  match to 0.1 (`RichTextTheme.lineMiddle`). No score moved; drifting
  lines 587 -> 530.
- **A floating object's anchor keeps the line's strut (2026-10-16;
  Linux).** A picture in the line drops the strut so the line can grow
  to it; a floating object taking no room counted too, and its line
  went to the engine's height and baseline: zh-a7728bc9's title after a
  text box's anchor stood 4.2pt low, now 0.2. No score moved; drifting
  lines 782 -> 773, none new.
- **An exact line set by its middle (2026-10-16; Linux).** With
  `w:textAlignment` "center" Word stands the text's own line in the
  middle of an exact one, not its baseline 13/16 down: zh-1563bd74's
  16pt articles in 30pt exact lines are 21.7pt down in Word's print, ours
  were 24.4 (2.7pt low a page); now 0.3. Drifting lines 720 -> 698.
- **Song, Ming and Mincho in a serif on Linux (2026-10-16).** Every
  CJK face drew through Noto Sans CJK; Word's 宋体, 細明體, ＭＳ 明朝 are
  serifs. A face may name its own fallback (`RichResolvedFace.fallback`),
  and those names take Noto Serif CJK SC/TC/JP there, the Latin stand-in
  still first. Tried first as the run's whole face: Noto Serif CJK's own
  digits and letters broke the PMingLiU documents' lines (zh-04f73697
  100% -> 66.6). As kept, no score moved.
- **A table set out by its first cell's margin (2026-10-16; Linux).**
  Before Word 2013's layout a table's edge stands its left cell margin
  left of its indent; the margin is the first cell's own `w:tcMar` where
  it states one, not the table's. zh-6143e5f0's plans (cells of zero
  margin) stood 5.4pt left of Word's. Sideways drift gone there and in
  two sibling reports, bug59058 363 lines -> 24; no score moved.
- **Justified lines keep their ideographic spaces (2026-10-16; Linux,
  engine patch).** skparagraph's justify spread U+3000 as a space: it gave
  its em up to the step, and a line's leading ones got none, so
  zh-1d3d66d3's "　　本會依據…" began 12pt into the margin. The engine now
  carries patches/skia-justify-ideographic-space.patch (applied by
  scripts/apply_engine_patches.sh; Skia itself stays upstream's): a U+3000
  is justified as an ideograph. Sideways drift 552 -> 537; no score moved.
  An engine built without the patch keeps the old placement.
- **A wrapping float set over content before its anchor is pinned, and
  that content moves under it (2026-10-17; Linux).** zh-06c46ba9 p70:
  the VML box "分工表格式" (square wrap, 3.6pt wrap distance above and
  below, 2.2pt under its paragraph's top) is anchored in "附錄3", after a
  table row parted onto the page. Word's print stands the box where the
  row's foot puts its paragraph and then sets the row's part UNDER the
  box, "附錄3" under that; ours drew the box over the row. Now the
  pagination notes such a float (one whose band, wrap distances in,
  reaches a table row set before its anchor on its page), pins it there
  (`_pinnedFloats`: page, band, where its anchor stood) and sets the
  pages again: the pinned band is on its page from the top, rows and
  their parts keep under it, and the float is drawn where it was pinned
  however far its paragraph then moves (`_floatShiftY`). An incremental
  setting keeps the pins of the pages it takes back unchanged. The wrap
  distances (`ImageFloat.distanceTop`/`distanceBottom`: `wp:anchor`'s
  distT/distB, VML's mso-wrap-distance-top/-bottom) are now part of every
  wrapping float's band; nothing else moved with them. zh-06c46ba9 95.5
  -> 97.3% (p70's box within 0.3pt, its table 2pt high of Word's).
- **A paragraph ending in a line break ends with its mark's own line
  (2026-10-17; Linux).** zh-17749c13 page 57: a paragraph of one bold
  仿宋_GB2312 `w:br` (YaHei to Word, two 15.6pt pitches) under a 12pt
  宋体 mark is three pitches in Word's print, the break's two and the
  mark's one; the grid's strut set both of ours at two, and everything
  after stood a pitch low to the end of the document. The last line of
  such a paragraph now counts as tall as `_markLineHeight` says (only
  where the strut set it taller; it holds nothing to draw).
  zh-17749c13 98.0 -> 99.9%; nothing else moved.
- **Wrong, taken out: "a first-line indent in a hanging indent's place
  takes the hang out of the inherited left" (2026-10-17; Linux).** Built
  from zh-15428325's one paragraph under "table of figures" (left and
  hanging 200 characters) naming only firstLineChars 200, which Word sets
  at the margin. The Windows box's lab in that package (Word for Windows,
  mode 14) keeps the style's left for such a paragraph; it is the
  paragraph's `w:numId` 0 that drops the style's indents ("a paragraph in
  no list takes no indent from its style", 60eb6371). Reverted; the
  document holds at 94.1% on that rule alone.
- **A right-aligned paragraph's trailing spaces after ideographs count,
  and wrap (2026-10-16; Linux).** Word's prints of two government
  footers, "红河县人民政府发布" (zh-1563bd74) and "沧源佤族自治县人民政府发布"
  (zh-c5b5087b), each in 14pt bold 宋体, `jc` right, five spaces after:
  the spaces run to the right margin, the text left of them (zh-1563bd74's
  "红" at 357.5; the engine, hanging them past the margin, set it 36pt
  right); and where they do not all fit, two stay and three make a line
  of their own, a line of the text's height (zh-c5b5087b's footer a line
  taller, every page's number and text 18.7pt higher). They are now set
  as held spaces, a zero-width break before each, at a space's width (the
  balanced half em where Word sets one), the breaks in the ideographs'
  style so the line keeps their height. Not after Latin text:
  zh-7dc3afad's "7,567 " figures stand as before in Word's print.
  zh-c5b5087b 83.7 -> 93.9%; zh-1563bd74, zh-f59a76e9 and three others
  closer sideways; nothing worse.
- **An empty paragraph overhangs the foot by the smaller of its mark's
  two faces' half leading (2026-10-16; Linux).** The last line on a
  gridded page may reach past the foot by its grid's overhang (the half
  of the box its face's natural height leaves). An empty paragraph's line
  is its mark's, and we took the East Asian face for it: zh-64044a1d's
  empty Body Text marks (12pt 標楷體 over Times) are one 18pt pitch, but
  YaHei's own box would be two, and its 7.7pt overhang kept a fourteenth
  empty line on page 97 where Word keeps thirteen (with "E1".."E17" in
  them ours parted as Word's). The Latin face alone instead broke
  zh-6d1afa56: its 14pt mark (Times over 方正小标宋) is two 15.6pt pitches
  either way, and Times' 7.55 left the page overfull, the page break
  after it then opening a blank page. The smaller of the two is right for
  both: zh-64044a1d 97.2 -> 97.7%; nothing else moved.
- **An exact row's own bottom line hangs under it (2026-10-16; Linux).**
  zh-ae655121's budget tables end on an exact 36.05pt row over a 0.75pt
  double line. Word's print centres the row's text in the whole 36.05 and
  sets the text after the table the line's 2.2 lower; ours took the line
  out of the row's room, so the text stood 1.1 high and the table 2.2
  short. Now the table's last row, when its height is exact, is that tall
  plus its cells' bottom line. zh-ae655121 93.8 -> 95.2%; nothing else moved.
- **Off the grid too, a paragraph whose every line holds its tallest
  stretch takes that stretch's strut (2026-10-16; Linux).** zh-d68ac84a's
  cells (`w:line="0" atLeast`, 宋体 with a Times digit opening the first
  line) set their first baseline 15.6pt under the rule in Word's print
  whether they hold one line or three; ours did on one line (the tallest
  strut, kept for single lines and the grid) and stood 1.6 to 1.8 high on
  two or more, where the engine split the mixed first line its own way.
  Now any paragraph whose lines each hold text of the tallest stretch
  gets that strut; one with a line that holds none (zh-1563bd74's footer,
  a 16pt "X" over 14pt text) is left as it was. Lines more than 1.5pt
  off Word's: 245 -> 225 (zh-d68ac84a 12 -> 0, zh-7dc3afad 12 -> 8,
  zh-799c91cd 8 -> 5); zh-d68ac84a 99.7 -> 99.8; nothing down.
- **A drawing group's lines and boxes, each in its place (2026-10-16;
  Linux).** A `wpg:wgp` group was drawn as its first child's shape
  stretched over the whole group, and its text boxes were one flow, each
  box pushed under the one before. zh-06c46ba9 p36 (a tree of fifteen
  labelled boxes and 27 connectors, the first a connector) printed as one
  diagonal line across the figure with the labels walking 140pt down the
  page; zh-6cd1befe p57's flow chart likewise. Now `WriterGroups` reads
  each straight line and rectangle (through nested groups, `chOff`/`chExt`,
  flips; `sysClr` and `lnRef`/`fillRef` theme colours) and draws them
  through `objectPainter`; a group whose boxes stand beside one another
  (one starts above the foot of the one before) lays out each later box
  alone, painted at its own top. zh-06c46ba9 94.5 -> 94.9; nothing else
  moved. Then every preset `PresetGeometry` defines (stars, block arrows,
  seals, bent connectors), turned and mirrored about its centre, with
  its line ends: zh-6cd1befe p57's flow chart now has its arrows and its
  "突发事件" burst; no score moved. And a shape alone that the layout's
  own outline (straight lines and boxes in RGB) leaves undrawn goes the
  same way: shapes-with-text's ellipse, triangle and theme-filled square,
  whose white text stood on nothing, and zh-454e2e29 p4's diagonal in its
  header cell; no score moved. Left: vertical text in a group's box, a
  lone line's theme colour and arrowhead, and Word clips a box's
  overflowing text.
- **Theme fonts by script, and in every part (2026-10-15).** A theme
  font reference names a slot: `majorEastAsia`/`minorEastAsia` the
  theme's East Asian face, which is its `a:ea` or, that being empty as
  it usually is, the face it lists for the document's East Asian script
  (`w:themeFontLang w:eastAsia`, zh-CN → `Hans`, zh-TW → `Hant`, ja-JP,
  ko-KR). The importer read every reference as the Latin face, so
  `asciiTheme="majorEastAsia"` set digits in Cambria where Word's print
  has SimSun; and it resolved none in headers, footers or footnotes.
  Both fixed, `w:eastAsiaTheme` with them. zh-1a3c7aa0 78.0% -> 91.7;
  nothing down. zh-a4b0f6ea's page numbers (a fit-to-text box, "— PAGE
  —") still differ: on two-digit pages Word wraps the closing dash onto
  a second line: see the next entry.
- **A header's or footer's fit-to-text box is sized on its first page
  (2026-10-15).** Labs `ftA`–`ftD` (zh-a4b0f6ea's package, twelve pages):
  its "— PAGE —" box, `wrap="none"` with `spAutoFit`, wraps the closing
  dash under "— 10" on every two-digit even page; changing the field's
  cached result changes nothing, and numbering from 8 — so that the even
  footer first stands on page 10 — prints every even page whole while
  the odd one, first on 9, wraps on each. Word sizes the box once, on
  the first page that header or footer is on, and later pages' text
  wraps inside that width. Ours fitted each page's box to its own
  number. But a field's result is one piece: zh-c3dd22c4's "- 10 -"
  (`numberInDash`) stays on one line in a box sized by "- 1 -" (Word
  halves its spaces to keep the box's width); so the spaces of a filled
  page number are joined to what follows, and an inherited box is never
  narrower than a paragraph's longest unbreakable piece. zh-a4b0f6ea
  82.0% -> 88.0, zh-5901e2b0 94.4 -> 100, zh-84702a67 91.5 -> 92.5;
  nothing down (against a clean baseline at the same tip). Not done: the
  halved spaces.
- **An "at least" row is that tall between its cells' margins; an
  empty hidden-mark cell asks nothing (2026-10-15).** Labs `rm1`–`rm6`
  (Word 16, modes 14 and 15): rows stated at least 28.65pt are 29.15
  with no cell margin, 29.9 with a 0.75pt top margin, 34.15 with 5pt
  above, 39.15 with 5pt above and below; the table's `tblCellMar` adds
  the same, a cell's `tcMar` replaces it, a row with no `w:hRule` is
  "at least" too, zero cell spacing changes nothing, and an exact row
  stays 28.65. Ours added only the rules. And an empty cell marked
  `w:hideMark` adds nothing to its row: zh-ae655121's floating signature
  table is 5pt shorter in Word with the marks than without, and ours
  counted the cells' empty paragraphs either way (which the missing
  margins had hidden). zh-a4b0f6ea's page-18 form 10pt short is fixed,
  +0.6; nothing else moved against a clean baseline.
- **A background brings a header and a footer (2026-10-15).** A document
  with `w:background` (never printed) and no header part is laid out by
  Word as if it had one: labs `bg1`/`bg2` (bib-chernigovka's package) —
  with the background Word's print holds two empty header marks (45.8,
  59.3) and a footer mark (803.5) and the body runs 85.7 to 783.8 down
  the page; without it, no marks and 68.2 to 793. The header is a line
  in Word's built-in Header style (Normal, single, nothing after) and
  then a Normal paragraph with its spacing (the body starts under its
  10pt after); the footer is the one Header-style line. The importer now
  adds such phantom parts to the layout's headers and footers only (the
  file's own are what a save writes). bib-chernigovka 0% -> 90.3, Word's
  16 pages; 61991 and 51921-Word-Crash067 carry the same marks but their
  margins already hold them. The art page border it also has changes
  nothing (lab `pb1`).
- **A line of spaces and tabs is its mark's line, single spacing too
  (2026-10-15).** The rule that a line holding only spaces takes the
  paragraph mark's size (2026-10-13) applied only where the style
  stated a line height to scale, and counted a tab as text.
  IllustrativeCases' paragraph of 11pt spaces and tabs under an 8pt
  mark, single-spaced, is a 9.2pt line in Word's print (its three empty
  lines fit under a table at a page's foot); ours set it 12.65 and the
  last went over, every line of page 4 a line low. Such spaces are now
  set at the mark's size and kept their own width by letter spacing,
  and a tab sets no line's height. IllustrativeCases 76.0% -> 100;
  nothing else moved.
- **A shape's text is set in its preset's text rectangle (2026-10-15).**
  A `wps` shape that is not a rectangle wraps its text inside the
  preset's `a:rect`, as Slides already did: shapes-with-text's "An
  ellipse with text inside" is two lines in Word's print, in the
  ellipse's inscribed box; the importer now adds the rectangle's margins
  (`PresetGeometry.geometry(...).textRect`) to the box's insets.
  shapes-with-text 37.5% -> 62.5; nothing else moved. Left: text in
  group shapes (`wpg:wgp`) — the importer takes the first body it finds
  and places it by the group; five corpus files have such groups
  (60316, shapes-with-text, zh-06c46ba9, zh-6cd1befe, zh-799c91cd).
- **A wholly hidden paragraph takes no room and draws no border
  (2026-10-15).** Its mark hidden — by its own `w:rPr` or by its
  paragraph style's `w:vanish` — and every run hidden, Word shows
  nothing of it: bug59058's HTML "Top of Form" paragraphs (style
  z-TopofForm, hidden, a rule under each) drew two rules in ours and set
  page 24 3.5pt low; its print has neither. `markHidden` had been read
  only by the writer, and only from the mark's own properties.
  bug59058 56.6% -> 57.1; nothing else moved. Its largest remaining run
  (177 lines from page 31) is OMML: Word typesets the equations in two
  dimensions, ours as a line of italic text, and everything after
  drifts — real equation layout is the next lever there.
- **Formulas written as text in Cambria Math (2026-10-15).** bug59058's
  equations are HTML-converted runs of math letters ("𝑘𝑖", U+1D400 on)
  in Cambria Math 13pt, with private-use characters (U+E037/E038) between
  them, and no spaces. Word: (1) sets the letters at Cambria Math's own
  widths (𝑖 0.3169 em; table generated from the Cambria Math in Word's
  DFonts, `CambriaMathAdvances.swift`) on Cambria's 1.172-em line; (2)
  keeps the space-free formula one word, so "was used:" ends its line and
  the formula opens the next; (3) sets a private-use character no face
  has at the run face's missing-glyph box, blank (Times' .notdef 0.7778
  em, 10.11pt at 13pt; Arial 0.75, Calibri 0.5068, Cambria 0.6582,
  Verdana 1.0 — `missingGlyphAdvance`), not a fallback's glyph, and does
  not part a line there. Ours now does all three, and draws the
  characters a math face takes from the platform's math face (STIX Two
  Math, 0.762/0.238 with 0.25 leading) at four fifths of the run's
  height, so its split of the height no longer makes the line taller:
  16.4pt lines became 15.4-15.8 (Word 15.2). bug59058 57.1% -> 71.9; it
  now runs 53 pages to Word's 52 — the remaining half point a math line
  is the next thing there (subscript runs and the private-use blanks).
  Then: the math face's characters at three fifths of the run's height
  (at four fifths they still made a line 0.2pt taller than Word's), and
  automatic spacing (`beforeAutospacing`) gives a list's FIRST item the
  web's 14pt — none only between two items of one list: Word sets the
  first reference 30pt under "References" (9pt after), ours had 24.7.
  bug59058 71.9% -> 73.9 against a clean baseline, nothing else moved.
  Tried and left: holding lines of near-equal run heights (Times "at
  least" 15 and Cambria 15.24) to the taller as one strut — Word's mixed
  reference lines are 15.2 and ours 15.5, but it cost bug59058 a point.
- **Leads measured and left (2026-10-15, late).** Each needs a Word lab
  or a deeper model; none is a quick rule.
  - Mixed faces on one line (bug59058's references: Times "at least"
    15pt with Cambria 15.24): Word's line is the largest ascent plus the
    largest descent of the faces, with the minimum applied to the line —
    15.2; ours gives each run its own "at least" height, which the
    engine splits by each font's own ratio, and the line comes out
    15.45 (lab `mx3`/`mx4`: removing the Cambria runs gives 15.0). A
    near-equal-height strut was tried twice and loses elsewhere; so
    does giving "at least" runs their natural height with the minimum as
    an unforced strut (lines 15.65, bug59058 to 39.9%: the engine's
    natural line counts each face's line gap, Word's does not). This is
    what keeps bug59058 a page long.
  - bib-chernigovka p15: an autofit two-column table whose 51.1pt first
    column (7.5pt margins, outset borders, 0.75 spacing) holds "90 лет"
    in bold 12pt on one line in ours and two in Word's — a third of a
    point either way.
  - bug57031 p11: the lower SAS table runs 2.7pt short by the page's
    foot (gaps between its tables, not its rows: Word's rows alternate
    21.1/21.4, ours 21.3, same mean), so a two-line "Note:" cell row is
    split there where Word carries it.
  - zh-e061a08e p1 (T16's lead): the framed page number is NOT it — its
    10pt line is shorter than the empty 12pt footer paragraph's 15.6;
    Word's footer top and ours agree (51.6pt up) and our last body line
    overlaps it by 0.2pt. A page-foot tolerance question.
- **A separated table is framed by its own lines (2026-10-16, T43).**
  A table that states its cell spacing (even 0, as HTML-converted tables
  do) draws its tblBorders top and bottom as a frame outside its cells,
  and the frame takes room, where every cell says nil for that side:
  bug57031's SAS tables (top 0.75pt, bottom 0.25) are framed in Word's
  print, each that much taller, and page 11 ran 2.7pt short without it.
  bug57031 87.0% -> 94.1, nothing else moved.
- **A line fits only above the page's foot, not on it (2026-10-16).**
  Labs `pf1630`-`pf1644` (Word 16): 33 lines of exactly 20.85pt (417
  twips each, 13761 together) fit a page whose text height is 13762
  twips or more and not one of exactly 13761 — Word wants the line's
  bottom strictly above the foot; ours took it on the foot, with a
  hundredth of a pixel to spare besides. The paragraph line-fit test now
  wants half a twip. No corpus document moved (zh-e061a08e's 0.2pt over
  the footer is decided elsewhere); the Slides session reports
  PowerPoint's baselines on the same 0.24pt raster, rounded down.
- **A page-anchored table parts after its first row when the text set
  under it leaves no room (2026-10-17).** zh-a4b0f6ea p20: the roster
  (`tblpPr vertAnchor="page"`, tblpY 183.4pt) fits whole on the page,
  yet Word's print keeps only its header row there. Rows 1-4 go to
  page 21, and "单位（盖章）", the line before it in the file, stays on
  page 20, set under where the whole table would end.

  Labs `t44/A`-`I` (Word for Windows, the page alone):
  - The table always stands at its tblpY. The board's earlier note that it
    dropped 41.9pt without the line was wrong: vAlign-centred cells
    merged down re-centre over whichever rows are on the page.
  - Word sets the line under the whole table (442 of a 505 foot),
    then takes the table up again from there. Row 0 fits; the 66pt
    row 1 does not, so it and the rows after it go over.
  - With the line after the table (lab C), or with no line (B), the
    table stays whole.

  Now, at a page-anchored table's first and second rows: if the
  whole table plus the text set under it plus row 1 would pass the
  foot, the text is placed where the whole table ends and the table
  goes on at the next page's head. The centred cells merged down
  from row 0 are then set in row 0 alone, with their overflow carried
  over, as Word prints "出生" on page 20 and "年月" on 21.
  zh-a4b0f6ea 89.0 -> 99.4; nothing else moved.

  Left: Word sets "出生年月" and "行政职务" 3.9pt lower in row 0 than
  the two-line cells beside them; ours sets them level.
- **Spaces beside other characters add no height to a line, in any
  face (2026-10-17).** zh-2a241df1's "（图表5…）" caption opens with two
  14pt spaces in 仿宋_GB2312, then 10.5pt 宋体 text, on a 15.6pt line
  grid. In Word's print it is one pitch; ours took two, and every line
  after it on the page stood 15pt low. The rule had already set such
  spaces at the text's size, but in their own face, and YaHei (Word's
  仿宋_GB2312 on a Mac) is two pitches even at 10.5. Labs `cap2` and
  `cap3` (Word 16): 14pt and 20pt spaces before, within or after the
  text leave the line as it is, in 仿宋_GB2312, YaHei, SimSun, Times or
  a face no one has, with the grid or without. A tab, a no-break space
  and a glyph do count. Now such a run of spaces has no height of its
  own (`height: 0.01`); a line of spaces alone keeps the mark's.
  zh-2a241df1 35.2 -> 72.4, zh-6cd1befe 98.2 -> 98.6; nothing down.
  Left:
  - Trailing 14pt spaces after 仿宋_GB2312 text are still a pitch tall
    (lab `cap`, `E-trail`). That is the trailing-space joiner's style.
  - The ideographic space is out of the rule. At no height, the line's
    baseline came 9pt low.
  - Without the grid, 20pt spaces in a 10.5pt Latin line (`cap3`) keep
    the line's height right but draw its text 9pt low, clipped by the
    next line. That was so before this change too.
- **A chart's data table is drawn (2026-10-17).** zh-2a241df1's two
  charts set their numbers in a table under the plot (`c:dTable`): the
  categories over the columns, then a row for each series with its key
  and name, and grey rules. This app drew none, and set the categories
  under the plot. In Word's print, at 10pt:
  - each row is 16.4pt tall, the categories' 16.1;
  - the last row ends 4.9pt over the frame's foot;
  - the names' column starts 17pt in from the frame;
  - the key starts 3.2pt into that column and is 19.2pt long;
  - the name starts 2pt after the key and ends 2.5pt clear of the plot;
  - the plot's top is 11.1pt under the frame's (ours was 4.3pt lower;
    changed only with a table).

  A line's key is its stroke. Over a legend at the foot, the table
  stops where the legend's band begins, as in Excel's print of the xlsx
  corpus' chart-ChartDataTable. zh-2a241df1 72.4 -> 93.3, and 97.1 with
  Slides' ten-step axis (cf320772); nothing else moved. Left:
  - Chart 1 stands 2.5pt lower than Word's. It is an inline object in a
    grid line, and chart 2's lands right.
  - The fills Word gives a chart with no `spPr` (c:style 2: light blue
    frame and plot).
  - Excel's newer charts key a row with a square, not a bar.
- **A chart's data table sets each row's text on one baseline
  (2026-10-17).** Word's print of zh-2a241df1 sets the table's Calibri
  digits and SimSun names 10.9pt into a 16.4pt row at 10pt, 0.27 em
  under the row's middle. Excel's print of chart-ChartDataTable has
  the same ratio (0.662 of the row). Ours centred each text's own line
  box. That set digits 0.7pt low and a row with a CJK name, which
  is a YaHei-tall line, 1.3pt low: three of page 1's lines missed.
  The second value axis's labels now take the first axis's 1.45pt
  lift too: "60.00%" stood 1.5pt under "500000", which Word sets on
  one line with it. zh-2a241df1 94.3 -> 97.1 on the Windows box;
  nothing else moved. The xlsx books with a data table or a second
  axis keep their pixel scores, and no pptx deck has either. Left:
  - chart 1 stands 2.2pt low;
  - the second axis's labels stand 9.2pt off the plot in Word, ours 6;
  - Word's plot is 3.2pt wider at the right.
- **A Roman numeral in East Asian text is the CJK face's (2026-10-17).**
  zh-78729cf9's "特别重大（Ⅰ级）、重大（Ⅱ级）、一般（Ⅲ级）" sits in a
  run of 仿宋_GB2312 hinted East Asian. Word's print draws it all in
  YaHei, each numeral a full 16pt cell. The classifier already counted
  U+2160-217F as East Asian under the hint, but the East Asian style
  is built on a Latin stand-in that has no such glyph, and the fallback
  reached DejaVu Sans (0.34-0.73 em) before YaHei. So the line took a
  character more than Word's, on pages 10, 16 and 17. Now those
  numerals are drawn from the platform's CJK face (YaHei on Windows,
  PingFang on the Mac, Noto Sans CJK on Linux), as dashes and
  ellipses already were on the Mac. zh-78729cf9 99.3 -> 100; nothing
  else moved.
- **A table in a text box is read (2026-10-17).** zh-64044a1d's
  附件十二, the 災民收容登記表, is a 27-line form inside a VML text box
  (419.65 by 428.75pt, behind the text). The text-box reader sets
  paragraphs only and skipped `w:tbl`, so the box held one empty line
  and the form printed as nothing (page 97: 8 of Word's 27 lines). Such
  a box's content is now noted (`_Shared.boxTables`), and the body's
  reader reads it again once the paragraph holding the box is set,
  tables and all, as it reads a small table in a cell into a box. It
  saves and restores its own state and the note and comment counts
  the box reader keeps. zh-64044a1d 97.8 -> 98.8 (page 97 23 of 27);
  nothing else moved. The only box in the corpus with a table.
- **A merged cell does not grow rows of exact height (2026-10-17).**
  In that same form, "離所方式" (a 5.5pt line and a 12pt one) is merged
  over two rows of exact 18.5pt. Word cuts the cell off. Ours grew the
  span's last row to fit the cell, 5pt, so the form's last four rows
  stood 5pt low. The stretch now skips a span whose rows are all exact.
  zh-64044a1d 98.8 -> 99.0 (page 97 now whole); nothing else moved.
- **A list item that is a picture alone has its number (2026-10-17).**
  chartex's third bullet holds nothing but an inline chart. Word prints
  the "•" at the margin, on the chart's line, its baseline at the
  chart's foot (379.4). A picture paragraph is painted on its own path,
  which drew no marker, and `_wordList` declines a paragraph with a
  picture. The marker is now painted there, from the paragraph's list
  level as for text, its baseline at the picture's foot (379.5).
  chartex 76.4 -> 77.8; nothing else moved.
- **A centred merged cell that does not fit its page's part centres
  the lines that do (2026-10-17).** zh-6d1afa56 p25: "《预算法》…" is
  nine 18pt lines merged over a 98.8pt row and an 80.8pt one, and the
  page breaks between the two rows. In Word's print five lines stand on
  page 25, centred in the 98.8 (17.2 under the rule), and the other four
  at page 26's top. Ours set the five from the part's top (13.2): the
  lift that brings a centred cell into the rows on its page took all of
  its spare room once the text was taller than the part. Now, when the
  text overflows the part, the lines that fit (by `cellCuts`) are
  centred in it. zh-6d1afa56 99.0 -> 99.6, zh-f59a76e9 98.4 -> 99.4,
  zh-a4b0f6ea 99.4 -> 100 (the roster's "出生年月" and "行政职务", 3.9pt
  lower in Word than the two-line cells beside them: the same rule);
  nothing else moved.
- **Under kinsoku off no mark hangs, and the layout's breaks have no
  spacing (2026-10-18).** zh-b00fef0d's Normal says w:kinsoku 0, and
  Word's print opens lines with "、" after "…协同更高效" and "，" after
  "…决策部署": a mark that may start a line goes to the next one rather
  than hang. And the zero-width breaks the layout puts in (before a
  closing mark under kinsoku off, at a quote) carried their run's
  spacing, 0.6pt each in a run spaced 12, uncounted by the fitter — "署"
  went down a line. zh-8f9b19f4 51.0 -> 72.0, zh-b00fef0d 93.5 -> 96.6,
  zh-76d361b2 +1.3, zh-361f01dd +0.3; zh-d68ac84a -0.1.
- **A quote that is its em to a hair keeps its squeeze (2026-10-18).**
  A full-width curly quote is padded to its em by a blank, an opening
  one's set as a word joiner that cannot be narrower than nothing. With
  Starling FangSong (f32d5151) on Linux the quote glyph is 15.99997 of a
  16pt em, the blank 0.00003, and the squeeze the line fitting asked of
  the quote went into that joiner and was clamped away: zh-8186c98d's
  "…中的标准计" lost its "计" (100 -> 31.8), zh-11701b00 and zh-15f67ef1
  fell too. A blank under 0.01pt is none now, and what a joiner cannot
  give the quote gives. All three back to 100; nothing else moved.
- **Two page breaks in a row leave a blank page (2026-10-19).** A
  paragraph of a page break alone, then one that opens with its own:
  the reader carried the first break onto the second paragraph, where it
  merged with that paragraph's own, and one page turned. Word turns two —
  lab `bb` (the Mac, Word 16): "甲" / break / "[break]乙" prints three
  pages, and either break alone two. zh-e74dd0a1's page 63 is that blank
  page, its folio alone, before "衢州市政府信息公开工作社会评议办法";
  ours ran two pages short from there. The paragraph is marked
  `pageBreakTwice` and the layout turns the page twice for it.
  zh-e74dd0a1 52.6 -> 99.4, 134 pages as Word's; nothing else moved.
- **A Wingdings bullet is Wingdings' width (2026-10-19).** The reader
  draws Word's private-use Wingdings bullets with stand-ins ("➢" for
  "Ø"), and the marker was measured at the stand-in's width, and in the
  text face's scaled size besides (16.05pt for 15pt 仿宋_GB2312).
  zh-3fe252ff's 15pt arrowhead is 0.794 em in Word's print (the width its
  embedded subset carries) and ends at 41.9pt from a 30pt first-line
  indent, short of the 42pt default stop where Word starts the text; ours
  ran past it to 63, every bullet's line held two characters fewer, and
  from p23 on its pages ran a line late. The marker now takes Wingdings'
  advance at the file's size, for the three bullets Word's prints give
  widths for ("Ø" 0.794, "§" 0.458, "l" 0.747). zh-3fe252ff 27.5 ->
  98.6, 94 pages as Word's; nothing else moved.
- **A row's footnotes go with the parts of it that mark them
  (2026-10-19).** zh-499adba6 is a book set in a one-column table without
  lines, a chapter a row; its first chapter's row runs from page 3 to 5
  and marks footnotes 1-8 on page 5, at whose foot Word's print sets
  them. Ours reserved a row's notes where the row began, and page 3 lost
  six lines to notes it does not hold. A row's notes are now set as a
  body paragraph's are: on the page where the row begins those marked in
  the lines that page holds, and the rest with the part of the row that
  holds each mark, as the row parts. zh-499adba6 9.8 -> 20.1 (its pages
  1-16 Word's now); nothing else moved. No unit test: the test process
  has no ICU to break the row's lines by.
- **A footnote parts under its mark (2026-10-19).** Word keeps one line
  of a note that does not fit under its mark and sets the rest first at
  the next page's foot, under the rule (lab `fn` on Windows, from
  zh-344a8d08's package: P13's three-line note, marked in the page's last
  line, one line on p1 and two on p2). Ours never parted a note: its
  mark's line went over with it, and the line before for company.
  zh-344a8d08's "(一)因應COVID-19疫情…", begun on page 3, marks notes 2
  and 3 on page 4, and Word sets 2 and two lines of 3 there. Two rules
  now: a note that does not fit parts at its last line boundary that does
  (a line at least), the rest carried to the next page's notes first; and
  a paragraph going on over a page takes there only the notes whose
  marks stand in the lines that page holds of it — it had reserved all
  its waiting notes at the page's head, then taken note 3 over with its
  mark and left page 4 its room empty. Notes keep to the document's line
  grid where their style does not say snapToGrid 0 (22.8pt a line in
  the lab), their separator does not. zh-344a8d08 19.9 -> 25.9; nothing
  else moved. (Its page 4 still sets all of note 3, where Word's falls
  0.8pt short of room for it.) No unit test: a mark's line is found by
  its text box, and the test process has no ICU to give one.
- **A merged cell that states no top takes the table's line
  (2026-10-19).** A cell merged down into a row rules it by the top line
  its continuation states, though nothing is drawn there; one that states
  no top at all now takes the table's line between rows, as any cell's
  unstated top does. zh-db07d44e's indicator table merges its first
  column down the rows, the other cells saying nil above and below, and
  Word's print sets its rows of at least 22.7pt 23.2 apart; ours stood
  22.7, two rows a page more. Its next table's continuations state nil
  above, and Word's rows there are 22.7 — a stated nil stays none.
  zh-db07d44e 33.9 -> 36.8, zh-d8247da5 93.3 -> 97.8, zh-33d025f6 +0.2;
  nothing lower.
- **An empty line keeps its paragraph's strut (2026-10-19).** A paragraph
  of stretches of several heights is held to its tallest where every
  line holds some of it; an empty line — a break after a break — holds
  no text to find, and cost the paragraph its strut. zh-0978dee9's cells
  of 10pt 仿宋 put "\n\n" between items, and one "•" set in the serif at
  a shorter line made the paragraph not uniform, so the tallest strut was
  its only hold; without it the engine shared the Latin stand-in's 13pt
  out by Liberation Mono's own depth, and every line with a digit stood
  13.86pt for Word's 12.96. An empty line whose own height is the
  tallest stretch's already now counts as held. zh-0978dee9 90.0 ->
  90.6 (its pp220-222 Word's); nothing else moved. No unit test: it
  needs the Office faces' stand-ins, which the test process lays out
  without.
- **A row taller than its page sets its long centred cells from the top
  (2026-10-19).** A centred cell whose text does not fit the part of a
  parting row on the page is set from its text's top, at the part's top
  — only for a row begun under other text, since a row that opens a page
  keeps its centring (zh-e37f8d40). Not a row that opens the page and is
  taller than it all the same: zh-0978dee9's rows of a 610pt list open
  their pages, their four long cells centred, and Word's print sets those
  cells' text from the row's top; centred in the whole two-page row,
  ours stood 3 to 48pt down every such page, and the document ran a page
  long. zh-0978dee9 90.6 -> 97.2, 322 pages as Word's; nothing else moved
  (zh-e37f8d40 among them).
- **A line may break after a hyphen before a digit (2026-10-19).**
  Unicode's rules keep a hyphen with the number after it; Word parts
  them where the word before has a letter in it, or the hyphen follows an
  ideograph. zh-15f60bac's "…公布之CNS11643-2(中文字…" ends a line
  "CNS11643-" in Word's print; ours took "CNS11643-2" down whole, and its
  tables ran a line long from page 16. Not inside a number alone: built
  for any hyphen before a digit, zh-64044a1d's telephone cells ("0932-
  757839", set "0932-75783" / "9" in Word's narrow cells) fell 99.3 ->
  93.8. zh-15f60bac 67.5 -> 97.8, zh-81aa310b +1.0, zh-5251dd23 +0.5;
  nothing lower.
- **A picture on a paragraph's last line keeps to the grid
  (2026-10-22).** A line holding a picture on a line grid is as many
  pitches as it takes — where the picture is alone in its line, or on the
  first of several. Not yet where it follows the text: zh-e49d7943's
  title "…演習編組表" has its 660.55pt picture after it in the same
  paragraph, on page 15 alone in Word's print, its line 37 18pt pitches
  (666); with the footer's 17.15pt YaHei line raising the page's foot to
  782.35 (lab `e49`, Windows), the empty paragraph and the next table's
  title row run past it to page 16. Ours, the picture's own 660.7, kept
  that row on page 15. The rest of the line goes under the picture.
  zh-e49d7943 77.4 -> 82.4; nothing else moved.
- **A nested table does not grow past a parent that spans its page
  (2026-10-22, T143f).** A table in an autofitting parent's cell
  autofits as any does, its cells' narrowest widening it. Where the
  parent already spans its page's text it has no room to give: Word
  keeps the child at its saved grid and lets the content overflow.
  drawing.docx's p9 banner table, 171.6pt in a 467.8pt parent beside a
  303.75pt logo, holds a 177pt picture (175.5 and its 1.5pt effect), and
  Word's print keeps the table — its right-set "Прозрачность открывает
  реальность" banner ending at 552.72 — where ours grew it to 177 and the
  banner stood 5.4pt right (the Mac's measurements). A parent with room
  still grows with its child (nested-minima: 200pt in 200, 241.5 in
  Word's print). Banner now 391.55-552.8; no line score moved. Left:
  Word clips a picture to the cell it overflows (the 175.5pt one and the
  logo end at their cells' edges in Word's print); ours draws it whole.
- **A row's part over the page keeps its cells' margins (2026-10-22).**
  What goes over of a parted row is a row again, no shorter than the
  height the file states — and, as for the whole row (labs `rm1`-`rm3`:
  an "at least" height is the room between the cells' margins), with
  the margins on top of it. zh-b378d8c4's 专栏5, one row of at least
  132.05pt with 15-twip margins, parts over pages 12 and 13; its part on
  page 13 is 134.4pt in Word's print, 133.0 in ours, and the page after
  it took the 22pt line Word sends on — every page after a line out.
  zh-b378d8c4 39.1 -> 100; nothing else moved.
- **A footnote's mark is on the line the page counts (2026-10-22).**
  Where a note fits is measured from the foot of the line its mark is
  on. Two ways that line was lost: a mark raised out of its line
  (`_paintScripts`) has no box there, and such a note was taken for one
  of no line and reserved whole — its line is now its neighbour's; and
  the line's foot was the engine's own line, short of the whole pitches
  a grid gives it. zh-344a8d08's note 3 is marked in a 16pt line of two
  22.85pt pitches, 45.7, whose engine line is 37.5: the note fit whole
  under it by 4pt in ours, and goes over by 4 in Word's print, its third
  line on page 5 (T144's one-line note 2 had left it the room).
  zh-344a8d08 25.5 -> 26.5; nothing else moved.
- **A number set right ends where its line starts (2026-10-22).** A list
  level's `w:lvlJc` right was drawn — the number ending at the first
  line's start — but measured as starting there, and its tab went on
  from a number's width too far. zh-f2ca3070's "i." and "ii." (lowerRoman,
  right, under a 7pt hanging indent) have their text at the indent in
  Word's print; ours, measured past it, went to the next default stop,
  16pt on, and every such item ran a line long from page 6. Centred,
  half the number is past the start. zh-f2ca3070 65.3 -> 98.5,
  zh-d746674a +0.3; nothing else moved.
- **A repeated header's line keeps its room over the row it stands on
  (2026-10-22).** A heading's line under it is the room between it and
  the row under it, whatever that row's own top: lab `hl` (Word for Mac,
  zh-e1b09977's calendar, the Mac's prints) — a 2.25pt line under two
  header rows takes its whole width under them, on the first page and
  under every repeat alike, the next row's text 13.68 under its foot.
  Ours gave the first row of a repeated page its own top line, resolved
  against the row above it in the file (half a point), and zh-e1b09977's
  later pages stood 1.7pt high (p14's rows now Word's to 0.3). Not over a
  row whose cells state their own top: zh-6e7ff836's repeats stand over
  rows whose tops say nil, and Word gives its header's double line no
  more room there. No line score moved: zh-e1b09977's p14 still keeps a
  line at its foot that Word's print sends on — the closing heavy line
  under a parted row's part, which Word draws under its last line
  (759.12-761.28) and ours lower.
- **A page's part of a table closes with the table's bottom line
  (2026-10-22).** A row that ends a page whole wants room under it for
  the line drawn there — the next row's top, as before, or the table's
  own bottom line where that is heavier. zh-77bd4900's tables rule 0.75pt
  between rows and 1.5 round them; Word's print closes page 18 under a
  1.44pt line (and opens page 19 under one), and its "Ex:第一期費用" row,
  ending 768.7 over a 769.9 foot, goes to page 19 for the 1.5; ours,
  asking 0.75, kept it. (Modes 14 and up, as the line under a row is
  counted; a parted row's piece keeps its own top line's width, as
  before.) zh-77bd4900 96.4 -> 97.4; nothing else moved.
- **A cell's floating objects are drawn outside its row (2026-10-22).** A
  paragraph shown whole that carries a floating object is not cut to its
  own lines, so the object stands where its anchor puts it — for the
  body's paragraphs; a cell's piece of a row is its `.text`, and was cut
  to the row. zh-e49d7943's "附件3" box, 36pt over the calendar's title in
  its first row, was drawn nowhere; zh-291fcea7's flow chart, text boxes
  anchored in a form's cells, lost nine of its labels on p5. zh-291fcea7
  38.9 -> 40.2, zh-e49d7943 +0.2; nothing else moved.
- **A raised footer frame wrapped round parts no row, sized or not
  (2026-10-23).** Rows part at a page's foot except under a footer
  holding a frame raised over its anchor that reaches above the bottom
  margin (labs `rw`/`rw2`, Windows) — but only a frame of a stated width.
  Lab `wr` (Word 16 Mac, zh-9462c6d6's package — the Mac printed it): its
  footer's auto-sized "- N -" frame, wrapped round and raised 15 twips,
  reaching 8.3pt over the 851 margin, sends a row of 16pt lines whole to
  the next page at 17, 20 and 33pt above the margin in modes 14 and 15;
  without the footer it parts from 20 (mode 14). A frame wrapped "auto"
  is not such a frame: zh-7654804a's, raised 955 twips, parts its p16 row
  in Word's print (Linux b2). A raised frame now counts where it has a
  width or wraps round. zh-9462c6d6 66.4 -> 100; nothing else moved.
- **A picture's line off its section's grid takes its multiple's extra
  (2026-10-23).** Off the grid, a multiple on a picture's line adds what
  it adds to its mark's single line, under the picture (lab `hp`) — but
  only where the section had no grid; a paragraph that leaves a grid the
  section has (`w:snapToGrid` 0) got neither that nor the grid's pitches.
  Lab `pn` (Word 16 Mac, zh-e68a2f57's package — the Mac printed it): its
  p7 chart, alone in a paragraph of 1.1 lines, snapToGrid 0, under a 9pt
  黑体 mark, sets the note after it 1.20 lower than at single, whatever
  the picture run's size. Ours now 1.03 lower; 0.66 is left, at single
  too, which the note's own spacing and first face do not move (labs
  pn-e/f) — the faces' metrics. No line score moved (sweep h134).
- **A merged label is centred down to a ghost-row group's part
  (2026-10-23).** A centred cell merged down over rows that do not all
  fit the page is set in the rows that do and the kept part of the one
  that parts there (`partingKept`), which weighed only cells of one row.
  A row whose cells are themselves merged over rows holding nothing parts
  only at one of those rows' tops (lab `mg`, Windows), and had none to
  weigh: zh-9ef811c8's "综合业务", merged from the row above into "监督检查"
  — merged over empty rows and parting at page 4's foot — stands centred
  down to that part's foot in Word's print (333.1), ours in its first row
  alone (289.9). Such a row now keeps the last ghost bound that fits:
  332.6. zh-9ef811c8 39.3 -> 40.7; nothing else moved (sweep h133).
- **A shape Word sets in Segoe UI Symbol gives its line that face's
  ascent (2026-10-24).** Lab `picln` (the Mac 7bd18d8e, Word 16,
  zh-e68a2f57's package; ~/starling-word-check/lab/picln): p7's 9pt note
  under its chart — 楷体_GB2312 over Times New Roman, 1.1 lines — stands
  its first baseline 10.89 under the picture in Word's print, ours 10.21,
  and its third line goes to p8 in Word's, every page after a line
  apart. Not the picture's line (it matches Word's to 0.1 at every mark
  tried): the note's "◎". Word sets the shapes of an unhinted run in its
  Latin face, and where Times has none — "◎◇◆★☆" — in Segoe UI Symbol
  (hhea 2210/-514 of 2048), whose ascent lifts the line: 0.48pt at 9pt,
  0.96 at 12, at single and 1.1 lines alike, in Word's 0.24 steps.
  "●□▲○■※" (Times has them) and "①△" (Cambria Math) lift nothing. Ours
  drew them all in YaHei, the line as any. Now the line holding one is
  as tall as Segoe's ascent asks: a joiner of Segoe's line where the
  engine sets the line, the first line's target baseline (and the
  paragraph, and its cuts, `_firstLineLift`) where a strut does.
  zh-e68a2f57's p7: 471.13 / Word 471.12, the third line on p8, 63 pages.
  Sweep h148: zh-e68a2f57 18.2 -> 92.1, 63 pages; nothing else moved.
- **Microsoft YaHei Light is a line of its own win ascent (2026-10-24,
  Windows references).** msyhl.ttc's usWinAscent is 2080 of 2048 where
  regular msyh's is 2167, the same 536 under (read off the Windows box's
  font by windows 01QbbApP; its hhea ascent, 2210, is the larger, so the
  hhea would go the wrong way): at Word's 1.3, 1.6605 em, the baseline
  (2080 + 0.15 × 2616)/2048. zh-a7a889eb's contents, each line's mark and
  page number 微软雅黑 Light 14pt at 0.8125 auto and 17.3 before, step
  36.21 in Word for Windows' print; at regular's 1.715 ours stepped 36.83.
  Word for Mac has no Light and sets regular's line (its print steps
  36.84), so Mac mode keeps it. Same-base sweep h149 (word-win): only
  zh-a7a889eb moved, 91.0 -> 90.7 — the contents' five lines now match,
  and p9's checklist, whose Light lines now stand within 0.05 of Word's,
  showed the next entry's 0.8pt a line that had cancelled against them.
- **Segoe UI Symbol is a line of its own ascent and descent (2026-10-24,
  Windows references).** seguisym.ttf, 2210 over and 514 under of 2048,
  1.330 em, beside Symbol and the Wingdings in the symbol faces' lines.
  zh-a7a889eb's p9 checklist cells — "☑12、…" with the box in a Segoe UI
  Symbol run over SimSun, 12pt at 0.8625 auto — step 17.16 in Word for
  Windows' print; the clone's (DejaVu Sans') line under SimSun's set each
  0.8 short. Same-base sweep h150 (word-win): only zh-a7a889eb moved, 97.2
  -> 97.9 (91.0 -> 97.9 with the line above and be77c1fa's bold).
- **Nunito Sans is its own widths and line (2026-10-24, Windows
  references).** Office's cloud font, which Word for Windows (its cloud
  cache) and Word for Mac both set and embed in their prints: a 1.364 em
  line by its typo metrics (1011 over, 353 under of 1000, no gap;
  USE_TYPO_METRICS on, so not its win 1.429), the baseline 1.011, and its
  Light, Regular and Bold widths over ASCII, Latin-1 and the common marks.
  The tables are Google's OFL variable font at wght 300/400/700 and its
  12pt optical size (at 6pt they are 5-12% wider): every width equals the
  subsets zh-d97c5474's and zh-8d72961c's prints embed and the cloud
  font's own, which windows 01QbbApP read off the Windows box. The
  stand-in was Carlito, about 9% narrower, its line 14.6 at 12pt to
  Word's 16.37. The two documents' Chinese runs (eastAsia, Word's MS
  Mincho and JhengHei) keep their own lines; they only stand lower, under
  the notices above that now take Word's room. Same-base sweep h151
  (word-win): zh-8d72961c 4.3 -> 36.2, zh-d97c5474 2.2 -> 19.6, nothing
  else moved. Their Greek, in Cambria runs, is the next entry.
- **Cambria's Greek is Cambria's widths (2026-10-24, Windows
  references).** Caladea, its stand-in, has no Greek, so the fallback
  (DejaVu Sans) drew it at its own, wider widths. Cambria's for U+0384 to
  U+03CE, regular and bold, were read off the Windows box (cambria.ttc,
  cambriab.ttf) by windows 01QbbApP; the 37 Greek glyphs zh-d97c5474's
  print embeds agree. zh-d97c5474's and zh-8d72961c's Greek notices, in
  Cambria runs under Nunito Sans Light marks, now break where Word's do.
  Same-base sweep h152 (word-win, on 497b95bc's refit): zh-8d72961c 36.2
  -> 53.2, zh-d97c5474 19.6 -> 39.1, nothing else moved.
- **Nunito Sans's own Greek letters (2026-10-24, Windows references).**
  It has five, Δ Σ Ω μ π, which Word sets in it where a Nunito run holds
  them: zh-d97c5474's "Δευτέρα" opens its Δ in the run before the Cambria
  one, 8.66 wide at 12pt (722 of 1000) in Word's print and 6.7 in the
  fallback's, and the line took a word more. Same-base sweep h153
  (word-win): zh-d97c5474 39.1 -> 50.0, nothing else moved.
- **A row opening a page under a cell of no top line takes the table's
  top line (2026-10-24).** zh-cec9d337's assignments table has a 3pt
  thinThickSmallGap top (sz 24) over single half-point inside lines, its
  cells stating single tops of their own but for some middle cells. Where
  a row opens a page the table goes on over — parted from the page before
  (p25, p26), or taken over whole because no line of it fitted the foot
  (p19) — Word draws the table's compound top line over such a cell
  (rects at 56.64 and 60.24 over p19's middle column alone) and sets the
  row's text under it, 4pt lower than ours; rows whose cells all state
  their tops open under their half-point line (p20-p24). The Mac's 10-18
  try, the table's top for every row at a page's head, cost this file
  84 -> 67; by the cell it is `headLift`, on the three ways a row opens
  such a page. Linux b2 found it. Sweep h147: zh-cec9d337 90.5 -> 99.8,
  zh-16e0a12a 99.4 -> 99.8. Same-base exception: zh-9c5d0c3f 100 -> 99.0,
  its ink moved to Word's — p4's table rows, 0.66-0.72pt high before
  (讓路 166.62 / Word 167.28), now within 0.15 (167.37), all but 單行道
  (461.9 before, 462.6 now, Word 458.6), which the scorer pairs anew.
- **A kept heading lets the next paragraph's first line reach past the
  foot (2026-10-24).** Off the grid, a multiple-spaced paragraph's last
  line on a page may reach past the foot by its extra (`_overhang`,
  zh-8112041b). The keep-with-next check asked for the next paragraph's
  first lines whole, extra and all. zh-34a6519a's "5.2.3 防台风Ⅱ级应急响应"
  (Heading 3, keepNext) stands under 表5-3-2's parted row on landscape
  p28 with 72.1pt left; it takes 44.3 and its paragraph's first 1.5-spaced
  line 30.9, 2.9 past the foot — inside it by the line's 10.3 of extra.
  Word sets both on p28 (456.2, 497.5); ours sent the heading and the
  paragraph to p29, and every page after ran a page-part late (Linux b2
  found it, reading it as the row's part). The check now allows the line
  its overhang, as the line set alone has it. Sweep h146: zh-34a6519a
  90.9 -> 99.8; nothing else moved.
- **A fitted box widened for a longer number keeps its right indent
  (2026-10-24).** A header's or footer's box fit to its text is sized
  once, on its first page (lab `ftD`), and widened on a later page for a
  longer field result where Word lets the paragraph run on whole. The
  first page's width takes the paragraph's right indent; the widening
  measured the line with its left indent alone. zh-9c162f26's "— PAGE —"
  (Times, hinted "default", a character in from each side) is sized by
  "— 2 —" at 61.65; "— 10 —" needs 68.5 with both indents, 58.2 without,
  so the box stayed 61.65 and the closing dash wrapped on every two-digit
  page — 33 extra lines. Both measures now take the right indent.
  Sweep h144: zh-9c162f26 97.2 -> 99.8; nothing else moved.
- **A list's last item in a cell keeps its automatic space after
  (2026-10-24).** Automatic spacing gives way at a cell's edges
  (a5df0942: zh-a4b0f6ea's cover form). Not under a list: zh-147bdae0's
  numbered commitments (Normal (Web), before and after automatic) stand
  14pt over their cells' bottom lines in Word's print — p24's "dex.html )"
  at 370.1, the next row's text at 406.1, where its one-paragraph cells,
  so spaced too, step 22.1 a row. The item's space before at the cell's
  top still goes (p44's "1." at 469.4 in both). Ours dropped both, and
  p45 stood 14pt high from its first row on, the table a page short of
  Word's by p46. A list item at a cell's end now keeps its 14pt, and a
  list "goes on" (no space between items) only within one cell.
  Sweep h143: zh-147bdae0 93.3 -> 95.5, p45 within 0.1pt of Word's;
  nothing else moved (the corpus's one file with such cells).
- **A row that states no cell spacing collapses its lines (2026-10-24).**
  Cell spacing was read for the table alone: one that states any, even
  0, rules each cell on its own, a row its own top and bottom line.
  zh-147bdae0's commitment tables state 0 and most of their rows
  `w:tblCellSpacing` of type nil in their `w:tblPrEx`; Word's print
  steps those rows one 0.5pt line apart, 21.1pt a one-line row (its
  first rows, 0 again in `w:trPr`, stand their lines in pairs), where
  ours took the line twice, 21.6. By p17's foot that was 3.7pt, and
  the last row ("公民社會團體、私部門或工作團隊", at least 48.8pt) found no
  room for its stated height and went over whole — Word parts it, two
  names on the page. Such a row now collapses its lines as a table of
  no spacing does (`rowsUnspaced`), and its `w:tblCellSpacing` goes
  back with the row's other exceptions. Sweep h142: zh-147bdae0
  92.8 -> 93.3, p17 within 0.4pt of Word's; nothing else moved (it is
  the corpus's one file with such rows).
- **A line of spaces alone is set in its mark's Latin face
  (2026-10-23).** Such a line takes the mark's size (prints of
  2026-10-13) and, for "　", the run's Latin face (8cc05b33). Where that
  face is the run's own — zh-1eeb9f9a's "　" cells, 9pt in a run whose
  `w:ascii` is 仿宋_GB2312, under a 12pt Times New Roman mark — the line
  was 仿宋's (YaHei to Word on a Mac) at 12pt, 15.84, two of the 15.6pt
  pitches; Word's print has them one pitch, Times' 12pt line. On p11 the
  row they stand in then went over whole, where Word parts it with two
  lines on the page. The line is now the mark's own face's. Sweep h141:
  zh-1eeb9f9a 96.2 -> 99.4, zh-4a90bb2f 96.5 -> 98.8; nothing else moved.
- **A centred cell set whole in the part keeps the parting row for a
  merge above (2026-10-23).** `partingKept` counts the parting row only
  where every one of its cells keeps something on the page, and read a
  centred cell's keeping from its cuts as the whole row's middle places
  them. zh-1eeb9f9a p8's "其他政策文件" — two lines centred in a 102pt row
  that parts with 68 left — ends past the foot there, though `splitRow`
  sets it whole in the part. So the row was counted as keeping nothing,
  and "公开渠道和载体", centred and merged down into it, was centred over the
  two rows above alone: 8pt below Word's, which centres it down to the
  row's four kept lines (62.4). A centred cell that fits the part whole
  now keeps it. Sweep h140: fourteen documents up, none down —
  zh-65e6c317 84.2 -> 100, zh-9ba2ead7 90.9 -> 92.6, zh-4197e764
  98.3 -> 99.6, zh-1eeb9f9a 95.1 -> 96.2, and ten by 0.1-0.7.
- **A parted row opens its next page with its own top line
  (2026-10-23).** A row's part that goes over to a new page was opened
  with the line above it and stood its text that line's width down. Lab
  `tb` (Word 16 Mac, zh-13552a3a's package — the Mac printed it): a
  one-column table whose cells state top nil and bottom single, a row
  parted at page 1's foot — page 2 opens with no line and the text at the
  margin (first baseline as row 1's on page 1); with the cells' top single
  4, a line at the head and the text 0.48 lower. Where every cell of the
  row says it has no top line, the part now opens bare (`_rowOpensBare`):
  zh-13552a3a's rows, top nil, stood 0.8pt low on every page they opened
  and now within 0.3 of Word's. No line score moved (sweep h131); its p28
  still sends "正）" over, a fifth of a point short.
- **A merged cell set whole in a row's part is drawn once (2026-10-23).**
  A centred cell merged down, whose text fits the part of its row on the
  page, is set whole there (`setWhole`); centred over all its rows, its
  text reaches past its own row's bottom in the flow, and the row's next
  part drew those lines again. zh-13552a3a's "4.就业失业登记", merged over
  rows 10-11, stands whole at page 15's foot in Word's print, and once;
  ours drew "失业登/记" again at page 16's head (the Mac's find). A
  column set whole in a part has nothing left for the parts after it.
  Drawing only — no line score moved (sweep h130).
- **A row's note with no room under its mark parts as a paragraph's
  does (2026-10-23).** A table row whose footnote did not fit under its
  mark's line left the note for later; where the row fit whole without
  it, the row was set whole and the note reserved only when the next row
  began — over the row's last lines. zh-499adba6's book is a one-column
  table, a paragraph a row, and its footnote 11, marked in the second
  line of the row "在重要政策領域…" near page 90's foot, parts there in
  Word's print and the row after its mark's line; ours set the row's
  seven lines whole and drew the note's 134pt over the last five. The
  row's note now parts where a line of it fits under the mark, else the
  page ends over the mark's line, as a body paragraph's (5c8d7006).
  zh-499adba6 and zh-9932bd83 87.9 -> 97.9; nothing else moved (h129).
- **A full-width percent sign may open a Traditional Chinese line
  (2026-10-23).** Word's Traditional Chinese line-start list does not
  hold "％" (its Simplified one does). zh-499adba6's "…占比為38.54" ends
  page 25's first line in Word's print and "％，女性理事…" opens the
  next; the engine, by Unicode's rules, keeps a number's postfix sign
  with it and took "38.54％" down, every line after two characters
  behind. Under the `zh-TW` lists a line may now part between a digit
  and "％". 40 documents up, all `zh-TW` with numbers before "％":
  zh-499adba6 87.4 -> 87.9, zh-afdd4a7e 95.5 -> 95.9, the rest to or near
  100; nothing lower (sweep h128, on the rebased tree).
- **A page's last line reaches past the foot by its own faces
  (2026-10-23).** The reach a grid line has past the page's foot was the
  least over every run of its paragraph. zh-c15af02e's p11 paragraph has
  a "%" in 新細明體 on its second line, a face whose line fills its one
  pitch but for 1pt; its fifteenth line, all 標楷體 in two pitches, ends
  5.4pt past the foot and is page 11's last in Word's print, where ours,
  taking the 1pt for every line, sent it on. Each line now has the least
  of the runs on it (`_lineOverhang`, found by the runs' caret lines),
  and the line that ends the page reaches by its own. zh-17749c13, whose
  two faces set the old rule, stays at 100. zh-c15af02e 66.5 -> 79.7;
  nothing else moved (sweep h125). The test of it skips in the full
  suite, where other tests' fonts leave no size to set it up with.
- **A grid line does not hang into the footnotes (2026-10-23).** On a
  line grid a page's last line may reach past the foot by the leading
  its face leaves (`_overhang`); over the page's notes it may not. zh-
  c15af02e's page 6, 45.7pt lines over a one-line note, holds thirteen
  in Word's print — the fourteenth would reach 4.3pt into the
  separator's line — where ours kept fourteen. Where the page holds
  notes, the line ends above them. zh-344a8d08 65.9 -> 99.8 (its p5 foot,
  the board's thirteenth line), zh-c15af02e 52.0 -> 66.5; nothing lower
  (sweep h124).
- **A line whose note has no room under it goes over with it
  (2026-10-23).** A footnote that did not fit under its mark's line, and
  had no line of it to leave there, was put off to the next page alone
  and the line stayed. Word takes the line over with its note:
  zh-c15af02e's footnote 1, one line, is marked in the line that would
  end page 5, and Word's print opens page 6 with that line and the note
  at its foot (office1 found it). The page now ends over the marking
  line, and the note goes over as before. zh-c15af02e 15.3 -> 52.0,
  zh-344a8d08 27.8 -> 65.9; nothing lower (sweep h123).
- **A parted row's part is closed with the table's bottom line
  (2026-10-23).** The line drawn under a row's part at a page's foot
  took the table's inside width. Word closes it with the bottom line
  where that is heavier, from mode 14 on, straight under the last line
  kept: lab `ef2b` (Word 16 Mac) 770.40-772.56 under a third line ending
  770.3, ours now 770.30-772.55 (a 0.5 line at 772.3 before); zh-e1b09977
  p14's part, 2.16 in Word's print, was 0.5. Drawing only.
- **A table's sides are drawn at their own widths, its top and bottom
  inside its rows (2026-10-23).** The painter stroked every ruled edge
  at the table's one width, and a side the file states wider or thinner
  (`edgeWidths`) took room in the layout but was drawn at that width:
  lab `ef2b`'s 2.25pt bottom under 0.5pt sides came out 0.5. Each side
  now has its own width; the table's top and bottom lines stand wholly
  inside the room their rows keep (`ef2b`'s bottom 782.3-784.55 against
  Word's 782.40-784.56, where centred on the edge its lower half was cut
  off with the row; zh-77bd4900's p3 tables open under a line at 68.7,
  Word's 68.64, ours 67.6 before). Drawing only; no score moved.
- **A row parted at the foot is closed with the table's bottom line
  (2026-10-22).** Lab `ef2b` (Word 16 Mac, mode 14, zh-e1b09977's
  package): a last row of four 17pt lines over a 2.25pt bottom line,
  with 15 to 25pt left under its third. Word parts it after the third up
  to 19 and keeps all four from 20 — the fourth must fit with the heavy
  line under it, and the part on the page is closed with that line.
  Ours left room for the row's top line (0.5) under the part, took the
  fourth for a line that fits, found nothing left to send over, and took
  the row over whole at 18 and 19. In the table's last row, from mode
  14 on, a cut now leaves the bottom line's room (`ruleClosing`); a cell
  that ends on the page is judged as before. No corpus score moved.
- **A style's page break before is the paragraph's (2026-10-22).** The
  reader takes a named style's paragraph properties with
  `RichStyleSheet.apply`, which keeps the paragraph's own break, as an
  edit that restyles a paragraph must — so a style's `w:pageBreakBefore`
  was never read. zh-499adba6 (and its twin zh-9932bd83) give Heading 2
  the break; Word's print opens page 23 with "（一）權力、決策與影響力"
  and each part after it on a page of its own, where ours ran on and the
  book was three pages short. Read from the file, the style's break is
  the paragraph's now, and a paragraph's "off" undoes it — but not on an
  empty paragraph that only ends a section: the contents section ends in
  an empty Heading 2, and Word's print has no page for it (the next
  section's page is the break). zh-499adba6 and zh-9932bd83 27.0 -> 87.4,
  99 pages as Word's; nothing else moved.
- **A border of none is no border (2026-10-18).** Under balanced widths
  the automatic space doubles inside text ruled round (labs `ap1`-`ap4`),
  and the test was only that the run carried a `<w:bdr>`. zh-f10c8f34's
  body runs carry `<w:bdr w:val="none"/>`, and Word sets "14号" 2pt apart
  (a quarter of its 8pt) where ours set 4; every line held a character
  less, and "…布局合理、" went over by the difference (lenovo-3 found the
  2pt in the Mac's measure). The test reads the element whatever the
  order of its attributes. zh-f10c8f34 74.4 -> 100; nothing else moved.
- **A line fits to two thousandths of a point, not five (2026-10-18).**
  The fitter took a stretch as fitting up to 0.005pt past the line.
  zh-0978dee9's cell line "《中华人民共和国河道管理条例》（2018" is
  120 + 8 + four Courier New digits (1229/2048 of 8pt) = 147.203pt of a
  147.2 line, and Word wraps "（2018". At 0.002: zh-1b82f5d7 98.0 ->
  100, zh-785d6dff 97.5 -> 99.5, zh-0978dee9 +0.1; nothing down.
- **The line match reads lines by their baselines on Linux
  (2026-10-18).** Off the Mac the line match reads PDFs with PyMuPDF,
  whose line bottoms are the faces' boxes: Word's fonts report their
  descent, ours (Type 3 glyphs on Linux) their ink, and the same line
  read 2-4pt apart, past the match's 3pt — zh-264d7516 84.6 on Linux to
  the Mac's 95.0, scattered over every page. A line is now read at its
  pieces' baselines, a fifth of each size under (the raised-text cap of
  earlier today folds into it). Same PDFs rescored: mean 94.4 -> 94.6;
  zh-264d7516 96.2, zh-6a4fc013 94.1 (its Thai), zh-8f9b19f4 92.4 (the
  Mac's 92.3), zh-340d52e9 75.3 (75.6), 60316 97.0 (the Mac's 97.0); down
  only zh-0cd63a22 100 -> 97.8 (two "◎" lines). Linux scores before and
  after this are not to be compared.
- **Text set under a parted page-placed table stays on its page
  (2026-10-18).** Text before a table placed against the page that would
  run into it goes under it, at where the whole table would end (lab
  `t44/A`, 442 of a 505 foot). Where that is past the foot, Word sets it
  as low as still stands on the page: zh-60173bb6's "附件1" title, three
  28.8pt lines before a table placed 248.5pt down whose whole would end
  at 734, is at that page's foot in Word's print (626-685), the table's
  first row above it and the rest on the next page; ours took it to a
  page of its own and the table a page on. zh-60173bb6 77.0 -> 97.5 and
  Word's 15 pages; nothing else moved.
- **An exact last row's thin bottom line stays inside it (2026-10-18).**
  A table's last row of exact height had its bottom line hung under the
  height, from zh-ae655121's 0.75pt double line (2.2pt thick), which
  Word's print sets that much higher than the text after. The Mac's lab
  `rb` (Word 16, mode 14, zh-5c6ff0d7's package) has an exact 567-twip
  last row ruled sz4 under at 28.32pt between its rules' centres, ours
  28.84: a single thin line stays inside. Now only a line over 1pt
  hangs. zh-5c6ff0d7 97.8 -> 100 and Word's 2 pages (its closing note
  had lost the page by 3 twips); zh-06c46ba9 97.3 -> 97.0, whose text
  under p70's table already stood 5pt higher than Word's and now 1pt
  more — a gap of its own, open.
- **Word's Thai faces on Linux (2026-10-18).** The Mac set Word's Thai
  faces to Cordia New's widths, their Thai drawn by the platform's
  fallback at a class scale (ea3ee2a9: 0.75 for Thonburi, 0.729 for
  Leelawadee UI); Linux kept its fallback unscaled. That fallback is
  Noto Sans Thai: shaped over zh-6a4fc013's Thai it sets Cordia's text
  at 1/0.70 (regular; 0.73 bold), and 0.66 sets the document's 614
  lines on 26 pages as Word's print — 0.70 gives 627 on 27, unscaled
  726 on 30. zh-6a4fc013 26/30 -> 26/26 pages (81.3 -> 81.1: Word's
  Thai has no text layer to match, its embedded Browallia no cmap);
  nothing else moved. (Cordia's per-character Thai advances, from the
  Mac, are in hand should a finer fit be wanted.)
- **A turned cell's line: no squeeze, a closing mark hangs, and it
  starts short of its indent (2026-10-18).** The Mac's lab `tr` (Word
  16, zh-cec9d337's package, tbRlV cells in a 138.9pt row, ind 113 a
  side, 12pt): "宜蘭縣（震災，內政部）" is one column at a full 12pt a
  character, its "）" 2.6pt past the row's foot, where eleven
  ideographs make two columns; the line is the row less both indents,
  and it starts 2.25pt short of its indent (3.4 under the top at ind
  113, 17.7 at 400). Ours squeezed "（" and "，" to fit and started at
  the indent. Now a turned cell's marks give nothing, its closing mark
  hangs as in the body, and a line set from its start (not centred,
  right or distributed: zh-701eda18's "個人申請" fell 0.4 under it)
  starts 2.25pt up. zh-f2835e26 72.8 -> 76.1, zh-cec9d337 +0.3,
  zh-51af781b +0.1; nothing else moved. (Lab `tr` with ind 0 starts
  9.8pt down, not built.)
- **A list number past its indent tabs to the paragraph's next stop
  (2026-10-18).** With a hanging indent, the text after a number goes to
  a stop of the paragraph's own before the indent, else the indent;
  past it, ours went straight to the default stops. zh-cec9d337's
  "（十七）" ends at 60pt over a 49.65pt indent, with stops at 49.65 and
  63.8, and Word starts "4月20日…" at 63.8; ours at the default 72, and
  the line lost its "完". zh-cec9d337 +0.1, zh-7773163d +0.4; nothing
  else moved.
- **Where the East Asian line rules are off, a Latin ")" after an
  ideograph may start a line (2026-10-18).** zh-51af781b's "Table Text"
  style says `w:eastAsia` en-US, so its text has no East Asian line
  rules, and Word's print (the Mac's note) ends a cell line "…得1 分"
  with "；" whole and opens the next with ")" — the row 11pt taller.
  Ours kept "分)" together and squeezed the "；" to fit it. Under rules
  off a break already stood before a full-width closing mark; now
  before ")", "]" or "}" after an East Asian character too.
  zh-51af781b 85.5 -> 94.3; nothing else moved.
- **From 2013's layout a half-hung mark gives its blank half too
  (2026-10-18).** Under `w:useAltKinsokuLineBreakRules` a closing mark
  hangs by half an em. From mode 15 on its other, blank half gives as
  any mark's does: zh-c2c92639 ends "…保证车辆冲洗干净；" 16.75pt over, the
  "；" 5.25 past the margin and two commas giving 11.0 — 0.47 short
  without the "；"'s own half; ours sent "净；" down, and pages 20-22 ran
  a line late. Not before 2013's layout: zh-1563bd74 (mode 14) leaves
  "…民政部门，" 21.75 over with one comma to give, and the rule there
  cost seven files (100 -> 58 the worst). zh-c2c92639 91.9 -> 97.8;
  nothing else moved.
- **A continuous last section of columns is a row too (2026-10-18).**
  A section of columns filled by column breaks, continuous after another
  on its page, is read as a borderless table row (T2); the reading
  looked only at sections that end at a paragraph, and the document's
  own last section ends at the body. zh-8f9b19f4 ends "填报人：" |
  "审核人：" | "负责人：" in three columns of a continuous section — one
  line in Word's print, and in ours a page each, the column breaks
  page breaks under T101's one column: 16 pages -> 15 (Word's 14).
  The line match does not see it (the names are not in Word's text
  layer). A document of one section keeps its columns. Left: the row
  parts over page 14's foot, which Word's holds.
- **A bracket after an ideographic space is no line's opener
  (2026-10-18).** An opening mark a line starts with keeps its blank
  half (lab `ls`), and the test for "starts with" skipped every space
  — U+3000 too. zh-70094a34's clauses open "\u3000\u3000（二）…", and
  Word's print takes "…设施区域范围内，" 21.75pt over with that "（"
  giving its half beside the "）" and the comma's half hang; ours sent
  "内，" down and every such page ran a line long. An ideographic space
  is a character of the line, and a bracket after it gives.
  zh-70094a34 85.3 -> 99.5; nothing else moved. (Tried first and
  reverted: under `useAltKinsokuLineBreakRules` a half-hung mark also
  giving its blank half — the same line's numbers, but zh-1563bd74's
  "…民政部门，" with one comma is left by Word, 100 -> 58.)
- **A right stop after a line that opens with negative spacing; an
  earlier section with no footer (2026-10-18).** zh-10e3a42b's first
  contents entry is "1．总则<tab>4", its "1" spaced -0.5pt, its dotted
  right stop 0.2pt inside the column. The engine moves a line on by half
  its first character's spacing (`TextLine`'s "fix for flutter"), so
  every edge the tab measure read was 0.25pt short, the tab 0.25 too wide,
  the line 0.05 past the column: the "4" took a line of its own and the
  contents page ran 17pt long. The measure now takes that half back where
  it pulls the line in (a push keeps the number drawn at its stop).
  zh-10e3a42b 87.7 -> 90.9, nothing else moved. And its first page,
  whose section names a header but no footer, printed the editor's
  footer line — the last section's "— 28 —"; a page of an earlier
  section that names none now shows none, as in Word's print (no line
  moves).
- **The line match reads raised text where it is drawn (2026-10-18).**
  Word prints `w:position` text with a text rise, and PyMuPDF's box for
  such a piece reaches down by the rise: zh-10e3a42b's clauses, 10.5pt
  up in 30pt exact lines, read 10.5pt low on Linux, while PDFKit on the
  Mac reads them as drawn (its 96.4 to Linux's 90.9). A piece set across
  now reaches no lower than 0.35 of its size under its baseline. Same
  sweep rescored: zh-10e3a42b 90.9 -> 99.8, zh-8f9b19f4 84.1 -> 88.5,
  zh-f2835e26 +1.0, four others +0.2; nothing down (turned chart labels
  and cells keep their boxes — capped, chartex lost 0.9).
- **On a line with word spaces corner brackets give nothing (T110,
  2026-10-18).** From 2013's layout, a line holding a U+0020 goes by the
  per-mark fallback test. The Mac's lab `sq-sp` (Word 16, zh-ea70c30e's
  p2, PMingLiU 12.5pt) leaves "有" 8.3pt over "…達 10,000 名的說" with
  three "「」" to give, and takes it once the spaces are gone. "No mark
  gives there" is wrong: Word takes the next character with round
  brackets giving on such lines — zh-5b7ae054's "（Big Data）…（Open
  Data）加", zh-e0ca7252's "（由機關填寫）…完", zh-c2c92639's "…处置技
  术" with "（）《" — and those three lost 0.1-5 points under it. So it
  is only 「」『』 that give nothing there. zh-ea70c30e 98.3 -> 99.3;
  nothing else moved.
- **zh-e0ca7252: six small things, 42.0 -> 98.0 at Word's page count
  (2026-10-17).** (1) An EQ field that rings a number with no result
  written, `eq \o\ac(○,1)` (27 of them opening its insurance clauses), is
  read as the circled number — Word draws the two overlaid, an em; dropped,
  each line took two characters more. (2) From 2013's layout a Latin word
  at a body line's end is taken, as before it, where the marks and
  automatic spaces can give what it needs and it starts half the
  character before it inside the margin: "…於109年6月15" takes "15" 7.8pt
  over with 24.5 to give, and leaves the line before its "109" (22.6 of
  22.75, starting 2pt in). (3) A Latin ")" hangs past the margin as a
  Latin comma does there: "…免載於招標文件)" ends 4.2pt over. (4) With a
  hanging indent in twips beside a leftChars count the left indent is the
  count and the hanging together, as w:left says in all 107 of the
  corpus's such paragraphs ("（六）…", leftChars 100, hanging 567: 12pt
  in, the rest at 40.35). (5) A cell's text direction lrTbV is
  horizontal (its rows a 12pt line in Word's print; ours turned it and
  its 29 empty rows were 4pt). (6) A section's last paragraph holding
  nothing but a floating object that takes no room takes none itself:
  the note box under each equipment list hangs past the margin in Word's
  print, where ours opened a page with it. Nothing else moved
  (zh-1b74ed91 +0.3 from (4)).
- **What an embedded subset lacks is set in the name's own face (2026-10-17).**
  zh-92373179 embeds a subset of 仿宋_GB2312 (FangSong_GB2312; its cmap
  holds 为 and 招 but not 规, 信, 运, 易, 贡 …). Word draws the subset's
  characters in it and the rest in the face the name has unembedded —
  YaHei, on a Mac — and the line takes that face's height and baseline:
  its 1.5-spaced 16pt paragraphs (snapToGrid 0) are 41.2pt a line in
  Word's print, YaHei's 27.44 by 1.5, where the subset's square measure
  made ours 31.2, and their baselines YaHei's. An embedded face's
  `cmap` is now read (formats 4 and 12), and where the name stands in
  for YaHei unembedded, a character outside it is set in YaHei (its own
  run kind in `_span`), and a first line holding one takes YaHei's
  baseline. zh-92373179 39.9 -> 46.1; nothing else moved. Most of what
  is left there is the matcher's: Word's text layer has no Unicode for
  its 招 (U+0000), and the document says 招标 on most lines.
- **YaHei's circled numbers are an em (2026-10-17).** zh-34a6519a p11:
  Word's print sets "①".."⑤" in Microsoft YaHei (its 仿宋_GB2312), 12.0pt
  apart at 12pt and 10.5 at 10.5. The YaHei stand-in has none, and the
  fallback that drew them (DejaVu Sans) is 0.9 of an em: "⑤有应急抢险任务…"
  then took "承" on its first line by squeezing its two "，" (5.5pt over,
  under half an em) where Word's, 6.75 over, goes on — a line short there
  and every page after early. They are an em in both of YaHei's faces now.
  zh-34a6519a 28.1 -> 90.8 on Linux, Word's page count (the Mac, whose
  fallback is em-wide, had 90 already); nothing else moved. With it, a
  1.5-spaced paragraph's foot overhang (a multiple's extra under its last
  line) takes the line's advance where the lines keep their fractions:
  on the Mac YaHei's ascent and descent (644.8) outran the advance (617.4)
  and its larger third let p5 take "（3）依法实施" with 0.5 to spare.
- **A table set in a frame stands where the frame says (2026-10-17).**
  zh-621d8756 p15: every paragraph of every cell of the form table carries
  one `w:framePr` (vAnchor text, y 342, xAlign center, wrap notBeside),
  which is how Word writes a table put in a frame. Word's print sets the
  table 17.1pt under "需要补正内容如下：", the text under it; ours read the
  frames in the cells as nothing and sat the table on that line's foot.
  Such a table now reads as a floating table does: the frame's y below the
  text's place (`floatOffsetY`), centred on the margin where it says
  xAlign center. zh-621d8756 82.3 -> 83.9; nothing else moved.
- **A Word paragraph's height and spacing keep their fractions too
  (2026-10-17).** With Word's lines kept unrounded, three roundings were
  left: the bridge reported each line rounded (its lines no longer added
  up to the paragraph, and the layout parts a paragraph at those sums),
  each paragraph's block was rounded up to a whole unit, and its space
  before was rounded and the space shared with the paragraph above
  rounded down. At a screen's 4/3px a point that set Word's 14pt web gap
  at 14.75 here and 15.23 on the Mac (testWebSpacingPartsTwoLists); in a
  conversion's twentieths of a point it is a hair a paragraph. All four
  are exact under Word's rules now (engine cac609985ae for the lines).
  With the exact spacing zh-d68ac84a's p36 table took a row more (0.53pt
  left, mode 14), so the half-line reserve of T87 is for mode 12 only:
  mode 14 asks the whole line, as 15 does. zh-799c91cd +1.2; the rest
  moves 0.1pt or less (matcher noise, up to 4 points on zh-232090e0's
  vertical cell text).
- **Word's lines keep their fraction (2026-10-17).** skparagraph rounds
  each line's height to a whole layout unit; Word does not. A 12pt
  PMingLiU line is 1332/1024 em, 15.61pt: zh-de3410bd's page 1, forty
  such lines under three headings, ends at Word's foot only with the
  fraction (rounded to 15.6, its last two lines fit with 0.35pt to spare
  and Word's print takes them to page 2; Word's lines step 15.6 with a
  0.24 every 33, its print's 1/300in grid). An engine patch
  (`skia-fractional-line-heights.patch`: `ParagraphStyle::
  setFractionalLineHeights`, bit 13 of the bridge's encoded paragraph
  style) keeps the fraction where a paragraph asks; `TextPainter.
  fractionalLineHeights` asks, and the layout sets it for a Word
  document's paragraphs only — nothing else in the app changes.
  zh-de3410bd 93.9 -> 100, zh-d35cbbdb 89.7 -> 100, zh-232090e0 95.6 ->
  100, zh-e061a08e 94.3 -> 99.8, zh-6d1afa56 +0.2. Three fits that
  rounding had won were fixed first, each its own rule:
  - A face Word does not have and draws in Cambria (MinionPro-Regular,
    -It) is a line of Cambria's ascent over Times New Roman's descent,
    1.166 ems, not Cambria's 1.172: bug59058's 13pt-at-least-15 lines
    step 15.17 (29 lines) and 15.16 (69) in Word's print, Caladea's 15.24.
    With the fraction its page 38 had lost a line; now 100.
  - A row that ends a page in a file of a mode before 15 asks room for
    half the line under it, not all of it: zh-1a3c7aa0 p13's
    "5 O,O-二甲基…" row ends at Word's 495.6 under a 0.5pt line, 0.22
    above the footer's top (its page number's box puts that at 495.82);
    bug65649 (mode 15)'s 0.75 line with 0.6 left still goes over. With
    the fraction the row had gone over and the document ran 92 pages.
  - Balloon Text was dropped on import (no paragraph names it), so
    markup balloons were set in the 9pt serif; delins's are Tahoma 8pt,
    lines of Tahoma's 1.207 ems, stacked 15.06 apart as Word's are. Its
    first balloon, for two deleted paragraphs, still stands 6.6pt lower
    than Word's (Word lifts it into the gap above its line; the three
    other prints with balloons put the first at its line's top, as ours
    does), and the stack under it with it: delins 80 -> 45, the one loss.
- **A line a hair over its column goes over (2026-10-17).** zh-ae655121
  p4: the cell "(F)＝(D)－(E)", 14pt 標楷體 (YaHei's widths in Word on a
  Mac), measures 81.8535pt in a cell of 81.85; Word's print puts "(E)"
  on a line of its own, and ours kept it, because a line was allowed
  five thousandths of a point over its column. The allowance is now a
  thousandth, still enough for ten ideographs in ten ems. zh-64044a1d
  98.6 -> 98.8; nothing else moved.
- **A list number in its paragraph mark's formatting, not underlined
  (2026-10-17).** zh-9c5d0c3f p3: "四、常見交通標誌" has a mark of 18pt
  bold underlined over a run of 16pt; Word's print sets "四、" at 18pt
  (36pt for the two) and draws no underline under it, the text's from
  126pt on. Ours took the number from the first run (16pt, underlined).
  The same document's "一、" to "三、" (marks underlined at the text's
  size) and zh-90e0cea8's "12." (its mark underlined) carry no underline
  in Word's print either. The number now takes the mark's run
  properties where the file gives the mark any (else the first run's,
  as before), the level's own size over them, and an underline only
  where the level's `w:rPr` says one; a mark larger than the text
  makes the first line as tall as a number of that size, as a level's
  own size did. No score moved (the lines were already where Word's
  are); the number's size and the underline are drawn as Word's.
- **A parted row's part is as tall as the row says and as its cells set
  whole in it (2026-10-17).** zh-15728c84 p8: a row of 81pt at least
  parts over the page, its left cell's two lines on page 8, and a
  centred cell beside it ("每年至少开展（参加）/ 1 次政务公开业务培训") fits
  whole there. In Word's print it stands 4.6pt down a part of 81.3; ours
  stood 10.5 down. Labs `t32c` on Word for Windows, which prints the
  document as the Mac's print has it:
  - one line of that cell stands 20.5 down;
  - with no stated height, the part is that cell's own 72.4 (two 31.9
    lines and 8.5 after) and the cell stands at its top.

  Ours centred the cell in the 64pt its neighbour keeps, which the cell
  overfills, and fell back to the room to the page's foot. The part a
  whole-set cell is centred in, and the part's drawn height, are now the
  largest of the row's stated height, the kept cells and the whole-set
  cells. All four labs within 0.1pt. zh-15728c84 98.5 -> 100,
  zh-1a3c7aa0 98.1 -> 99.8; nothing else moved.
- **A paragraph that is only a column break opens the next column with
  its line (2026-10-17).** zh-6cd1befe p51: a two-column section ("附件3"
  | the roster's title), set as a row of a borderless table. Between the
  columns is a paragraph holding only a column break. Word (for Mac, and
  for Windows alike) prints that paragraph's empty line at the second
  column's head and the title under it, 20.7pt lower than ours. The
  reader keeps a break-only paragraph's line on the page before, which
  is right for a page break, so ours left it in the first column. Now
  the column split carries it into the column it opens. The gap cells
  between columns also take no indents from their column's last
  paragraph: carried, that became "12", whose 56pt indent widened
  zh-a0e932c2's gap and moved its second column 16pt right (100 -> 78.8
  until this). zh-6cd1befe 99.4 -> 99.5 (p51 whole); nothing else moved.
- **An empty paragraph that ends a section is neither numbered nor
  counted (2026-10-17).** zh-e6d54ae4's first section ends on an empty
  paragraph holding a level-0 item of its "壹、貳、…" list. Word prints
  no number for it and numbers the next heading "肆、計畫內容"; ours
  counted it, and every heading after was one on ("伍", "陸", "柒、其他"
  for "陸、其他"). zh-e6d54ae4 99.2 -> 99.5; nothing else moved.
- **zh-540dc149's scoring form: a fixed table keeps its grid, and a
  centred merged cell lets its row part (2026-10-17).** Two causes:
  - The form is `tblLayout` fixed, `tblW` 98% of a 640.6pt landscape
    column. Word rules its 638.6pt grid unscaled (borders 93.6 to
    732.2); ours scaled it to 627.7, and its cells wrapped a word
    early. A table whose grid is wider than its percentage share now
    keeps it, fixed or autofit (autofit ones already did).
  - Row 3 runs 3.8pt past page 5's foot. Its centred cell "（3）桥隧（8
    分）", merged down over rows 3 and 4, has no line to cut in the
    part, which counted as stuck and sent the row over whole. Word
    parts the row (its last cell's "扣完为止。" opens page 6) and
    centres that cell in the part. `splitRow`'s rule that sets a
    centred cell whole in the part now takes a merged cell with no cut
    there.

  zh-540dc149 35.9 -> 97.5 (Word's 10 pages); nothing fell. In the same
  sweep, with upstream's commits: zh-fec5fa30 85.1 -> 87.7 (it has
  fixed percentage tables and merged cells). Left: page 1's "(JTG
  H10-2009)", which Word wraps after "(JTG", and page 5's last lines.
- **On a grid that takes room away, a body line is whole cells of
  Normal's size (2026-10-17).** zh-f0bd9ea8 (mode 14, linesAndChars,
  charSpace -842, Normal 10.5, 16pt text) took a character more than
  Word on nearly every body line. Labs on its real first paragraph
  (`lab/f0b`, shifting the line with a negative `w:ind w:left` in twips,
  which leaves the grid's pitch alone; margins move it) found:
  - The justified lines end at 432.36pt in Word's print, 4.19 short of
    the 436.55 column. That is 42 cells of 10.294: Normal's 10.5 plus
    the grid's -0.206.
  - With the margin 5.1 or 10.1pt in, the lines end at 422.07 both
    times, 41 cells.
  - The squeeze rule held all along (a comma gives half a cell); the
    line was 4.19 too wide.

  zh-d68ac84a's 439.4 is exactly 30 cells of 14.647 (Normal 16), so it
  was right already. Now a body line on such a grid is as wide as the
  most whole cells the column holds. Not in a cell, and not in a header
  or footer, which keeps to no line grid: d68ac84a's footer "-1-"
  moved. Not where the grid adds room: zh-ac627439 (+0.3, 40.9 cells of
  10.8) sets lines past 40 cells, and fell 100 -> 75.5 with it.
  zh-f0bd9ea8 53.6 -> 84.1; nothing else moved.
- **An embedded object as wide as the column sends its paragraph mark
  to a line of its own (2026-10-17).** WordWithAttachments' document
  object (`w:object`, 468pt) stands in a 467.75pt column. Word's print
  sets the next paragraph a whole Times line lower than ours, and page 2
  opened a line high. Lab `wide`: an object, an empty paragraph and
  "Bravo", with the object's width varied:
  - in a 456.75pt column, the mark stays beside an object of 456.7 and
    drops at 456.75;
  - in a 467.75pt column, it drops at 467.48 (the 0.3pt there was not
    explained).

  A DrawingML picture keeps its mark beside it: bug57031's 480pt plots
  in a 468pt column fell 99.7 -> 92.6 with the rule, as did
  zh-06c46ba9, zh-15428325 and chartex. So the rule is for an object
  only, and not in a cell. WordWithAttachments 84.2 -> 100; nothing
  else moved. Left there: its VML WordArt (`v:textpath`) is drawn as
  grey boxes. Word prints it as pictures, which the line match does
  not score.
- **A style that is no child of Normal takes the defaults' language
  (2026-10-17).** zh-fec5fa30's Normal sets East Asian en-US, while
  its defaults are zh-TW and its body style "內文2" names no parent.
  Word keeps "，" off a line's start there and carries "目" down with
  it. Ours read Normal's en-US for the whole document, which has no
  East Asian line rules, and opened a line with the comma. Now:
  - where the defaults' `w:lang` differs from Normal's, it is stated
    on the root that unbased styles start from (as size, face and
    kerning already were);
  - the line rules read the run's language, then its paragraph
    style's, then the document's.

  zh-fec5fa30 84.7 -> 86.1; nothing else moved.
- **A repeated header of stated rows is repeated at their height, its
  cells merged down past it cut there (2026-10-17).** zh-fec5fa30's
  forms head with one row of 45.35pt (exact on the first form, at
  least on the others), every cell merged into a row under it that has
  no cell of its own, so ours folded that row's 34pt into the header.
  Word's later pages open with the header row alone: 45.0pt where it is
  exact, 46.4 (the height and its rule) where it is at least. A cell
  merged down past the header asks no room of it: "評核重點項目", 50pt
  with half lines before and after, stands centred in the 46.4. Ours
  repeated all 79.35pt, every row 34pt low.
- **An autofit cell's narrowest takes its first piece from where the
  first line starts (2026-10-17).** zh-fec5fa30's 附件2 calendar indents
  its day cells left 640, hanging 640, some right 560 too: "14" stands at
  the cell's edge. Ours counted the 32pt left indent against every
  piece, wanted 84.8pt for "14" in a 76pt column, and refitted the
  table; "18 連江縣" then wrapped and the calendar ran onto a 56th page.
  Word keeps the grid. Now the first piece is measured from the first
  line's start and the others from the left indent (not for a list
  paragraph, whose indents are the list's).

  Both: zh-fec5fa30 88.8 -> 94.2, Word's 55 pages; nothing else moved.
- **A line may open with "/" after an ideograph, and a centred merged
  cell parted at a page's foot keeps its lines down to the cut
  (2026-10-17).** zh-21421b7d's narrow cell "法人/其他组织" is "法人",
  "/其", "他组", "织" in Word's print: "/" is on no line-start list,
  so it parts from the ideograph before it, as a hyphen does. The
  engine kept "人/" whole and set "法" alone. Its "所需信息情况",
  centred and merged down over a page's foot, has ten 26pt lines in a
  part of 260.5pt; Word sets all ten from the part's top. Ours took the
  cell's bottom margin from the part too, although the cell's foot is
  on the next page. So it kept nine, centred them 13pt down, and
  carried the tenth over to push "况" down a line. zh-21421b7d 69.2 ->
  97.4; nothing else moved. Left: its last row's line takes two grid
  pitches in Word (one in ours), a 楷体_GB2312 line on a 15.6pt grid.
- **A line too narrow for one character sets every character on a line
  of its own, the marks too (2026-10-17).** zh-830ef10d's merged cell
  of 336 twips leaves 6pt for its 12pt "个性要求（6分）". Word's print
  sets eight lines, with "（", "6", "分" and "）" each alone. Ours kept
  "（6" and "分）" together, as the line rules ask. The engine, laying the
  line out 6pt wide, overflowed and kept "6分" together even with a break
  between them, so we set seven lines centred 9pt low. Now:
  - such a paragraph gets a break before every character;
  - the fitter keeps those breaks;
  - the engine lays the line out one em wide.

  zh-830ef10d 89.2 -> 97.3; nothing else moved.
- **华文新魏 (STXinwei) is Word's own face on the Mac (2026-10-17).**
  Word 16 carries STXINWEI.ttf, with hhea 0.8 + 0.236 and no line gap.
  At Word's 1.3 times that, a 24pt line is 32.3pt, which is three pitches
  of a 15.6pt grid. zh-424775e4's title, centred in them, has its
  baseline at 117.84 in Word's print (117.77 by that rule). Ours did not
  know the name, measured it as a Latin face's square stand-in and gave it
  two pitches, so every page after it ran 15.6pt early. Now the name is
  East Asian and has its own line. zh-424775e4 7.6 -> 87.3; nothing else
  moved.
- **A style's character spacing is the run's when the run says none
  (2026-10-17).** zh-5dc5ce34's Normal sets `w:spacing w:val="-6"`
  (-0.3pt), and its runs set nothing. Word sets its 16pt text 15.4pt
  apart: the spacing is counted twice on a full-width character under
  `w:balanceSingleByteDoubleByteWidth`. Ours read only the run's own
  spacing, set the text 16pt apart and broke every line a character
  early. A run's spacing is now its own, else its character style's,
  else Normal's, both where the run is measured and where a full-width
  character doubles it. zh-5dc5ce34 20.3 -> 22.7, its lines now
  breaking where Word's do. Checked against an older build (s124) only,
  which hid a fall: on one base zh-3c055c9b went 76.7 -> 33.5 (office1's
  sweeps). That was the grid, not the spacing — see "Ideographs off the
  grid keep its addition" below.

  What still holds zh-5dc5ce34 down is Word for Mac's alone. Its print
  sets every page of the first section 21.6pt lower. Above the body
  stand the header's 9pt mark (at 89.5) and a second, 16pt Normal mark
  at the left margin (115.4), although `header1.xml` holds one
  paragraph. Word for Windows prints the whole file without that second
  mark, its body at 127.3 to ours 127.7 (lab `c5e`). That needs a Word
  for Mac lab: the header alone, and with its `w:pBdr` removed.
- **A footnote stands on the page of the line that marks it
  (2026-10-17).** zh-424775e4's footnote 2 is marked in the fourth line
  of a paragraph whose first three end page 9. Word sets those three on
  page 9 and the note at page 10's foot. Ours reserved the paragraph's
  notes when it began, so the note took page 9's room and three more
  lines went to page 10. Now a body paragraph's note is reserved on a
  page only if the line holding its mark fits there with it; otherwise it
  waits for the next page. A note whose mark's line went over anyway is
  carried with it. zh-424775e4 87.3 -> 96.2; nothing else moved.
- **A Latin name Word has no face for goes by the file's font table
  before its name's look (2026-10-17).** zh-c399c91a's table sets its
  digits and "/" in "LinTimes": in the font table with the PANOSE of
  Times New Roman, no alternate, charset 00. Word's print draws them in
  Calibri, "/" 4.06pt at 10.5, as the table rule for such an entry has
  it. Ours read "times" in the name and took Times, "/" 2.92pt, so
  "1套/基层执法部门" kept "门" on its line where Word wraps it, and every
  row after it on page 4 rose 18.5pt. Now the serif guesses by name
  apply only to a name Word has, or one the table does not describe.
  zh-c399c91a 64.3 -> 100; nothing else moved.
- **What ends with a closing mark may take half an em of the automatic
  spaces (2026-10-17).** zh-7cf85f15's justified cell line
  "五、辦理112年與113年總資源…經濟預測。" (mode 15, PMingLiU 12,
  doNotCompress) takes "測。" 5.24pt over in Word's print. Its four
  ideograph–digit spaces are set at 1.62 of their 3.0, against 3.0 on
  that document's short lines. Ours capped what automatic spaces give at a
  quarter em, 3pt, and wrapped "測。". Half an em for every piece was
  tried and broke zh-c5f59397 (97.8 -> 87.7), whose "…噸級巡" leaves a
  plain "緝" 3.8pt over in Word. So half an em only where the piece ends
  with a closing mark, which no line may start with (zh-b13d0fb4's "度。"
  too); a quarter otherwise. zh-7cf85f15 76.5 -> 98.5; nothing else
  moved.
- **Across a cell's edge, contextual spacing keeps what is counted in
  lines (2026-10-17).** zh-fec5fa30's p47 header cells are contextual,
  with `beforeLines`/`afterLines` 50 on an 18pt pitch. Word's row is
  51.2pt: two 16pt lines and both 9pt halves. Ours took the spacing away
  between neighbouring cells of one style, 44.7. Not across every cell's
  edge: zh-1a3c7aa0's contextual cells over web spacing in points lose
  it in Word (keeping it, 99.9 -> 28.6, 93 pages to 90). So only the
  line-counted space stays, and only between two cells.
  zh-fec5fa30 94.2 -> 96.6, zh-92373179 41.6 -> 47.3; nothing else
  moved.
- **A table's text keeps off the line grid unless the file says
  `w:adjustLineHeightInTable` (2026-10-17).** zh-117cf7c6 (mode 15, a
  line grid of 18.25pt, no such compat) has a form of 12pt 標楷體 rows (YaHei
  to Word, a 20.6pt line) at least 26.65pt. Word's print makes them 26.65
  to 35.6pt, off the grid. Ours snapped each line to two pitches, 37pt,
  and the form ran onto a fourth page. The reader now takes the setting
  (`RichDocument.adjustsLineHeightInTable`), and a cell's paragraph in a
  file without it is off the line grid wherever the layout asks
  (`_offGrid`); the character grid is untouched. zh-117cf7c6 39.2 ->
  98.6, Word's 3 pages; nothing else moved.
- **A right or centred tab stop past the right indent is set at it
  (2026-10-17).** zh-c2c92639's "toc 1" puts its dotted right stop at
  13948 twips, past the page's edge. Word ends every entry's page
  number at the margin. Lab `tb` (Word for Windows, which prints this
  file page for page as the Mac does) tried right stops at 9000, 9600,
  9800, 11000 and 13948 twips in a 9264-twip line. Every one past the
  margin ends "123" at the margin, and a centred stop does the same.
  Ours ran the dots on to the stop and sent the number to a line of its
  own, so each entry took two lines and the contents a page more.
  Such a stop is now a right stop at the right indent, and in a
  justified paragraph its tab is not held: a held space is a little
  wider than the tab, enough to push the number over. zh-c2c92639
  9.5 -> 91.3, with Word's 54 pages; nothing else in the 148 moved.
  Still open: a *left* stop past the margin. Word gives the tab a line
  of dots of its own and starts what follows on the next line. Ours
  runs the dots past the margin and wraps once.
- **Ideographs off the grid keep its addition (2026-10-17).**
  `w:snapToGrid` 0 on a *paragraph* takes its Latin text off a
  character grid (zh-268f8d15's footer), but not its ideographs. Lab
  `sp` (Word for Windows) used zh-3c055c9b's package and its "表標題"
  style, which is off the grid and spaced -0.5pt. At 12pt on its grid
  of +1pt a character, ideographs are set:
  - 13 apart spaced 0;
  - 12 spaced -0.5, whether the style or the run says so (counted twice);
  - 10.6 spaced -1.2, 15.4 spaced +1.2.

  The body, a table cell and a text box give the same. On a grid of
  -0.5pt, 0 is 11.5. Ours left the grid's addition out, so once the
  style's spacing counted (above) its 47.8pt header cell held "支出傳票"
  where Word's print has "支出傳". Off on a *run*, the addition does
  go: zh-457a8d62's "(附件一，1頁)" runs say `w:snapToGrid` 0 and are
  set at the face's widths. (The run's property is the one the spec
  gives to characters; the paragraph's is for lines.) zh-3c055c9b
  33.5 -> 91.7, zh-92373179 39.9 -> 53.2; nothing fell.
- **An empty line beside a float wrapped round asks half an em
  (2026-10-17).** zh-d62da4dd's page 4 has two charts wrapped tight,
  each anchored in an empty paragraph that also holds a "單位" text box
  (wrap none), with empty paragraphs after them. Word keeps everything on
  page 4:
  - the first chart leaves its anchor no room on either side, so the
    anchor's line goes under it, and the "單位" box goes with that line;
  - the second leaves 10.95pt at the column's left, and its anchor and
    the empty paragraphs after it stand there.

  Ours asked a whole em (12pt) of every line, so it sent them all under
  their charts and the page ran onto a fifth. zh-37b6536f's empty
  paragraphs under its row of photos, which leaves 5.0pt, go under in
  Word: a fit from any room at all took that file 99.2 -> 95.4. Now an
  empty paragraph (or one of float places alone) asks half an em, both
  for its own float and for the ones above it, and a box in front of the
  text keeps to its paragraph's line when a float of the paragraph
  pushed that line. zh-d62da4dd now has Word's 4 pages; its score holds
  at 55.7, the rest being its charts' labels. Nothing else moved.
- **A table placed against the page stays whole while it ends above
  the footer's place (2026-10-17).** zh-0b87285b's 13-row list, at its
  tblpY on a landscape page, ends at 530.2pt in Word's print. That is
  past the bottom margin (523) but above the footer (545.4), and the
  whole table stands on page 6. Ours split at the margin, keeping the
  header row alone on page 6 and sending the rest over.
  - Measuring to the page's edge instead broke zh-6cd1befe (98.7 ->
    89.3). Its 26 rows would end at 832.8: on the page, but under its
    footer's 792.4, and Word parts them.
  - So the measure is the page's height less the footer distance (and no
    less than the margin).

  zh-0b87285b 77.9 -> 98.0; nothing else moved.
- **A section that names no page-number format writes plain numbers
  (2026-10-17).** zh-c8eb6e92's last section says `w:pgNumType
  w:fmt="numberInDash"` and its earlier ones say nothing. Word's print
  numbers those pages "1", "2"…, but ours wrote "- 1 -" on every page,
  taking the last section's format for theirs. zh-c8eb6e92 91.2 -> 97.5
  (zh-8e8d4c40 98.9 -> 99.4 with it); nothing went down.
- **A page break followed by floating objects alone is a break
  (2026-10-17).** zh-021b8feb's page 14 ends with a paragraph of a
  `w:br type=page` and a box "附表" (wrap none, 16.5pt down), its mark
  18pt bold. Lab `ab` (Word 16, four variants: as is, the mark at 12pt,
  the anchor's run at 18pt, the box removed) prints:
  - the box at page 14's foot, with the paragraph's start;
  - the next paragraph at 93.7 on page 15 in every variant, as with a
    break alone.

  Ours made the rest of the paragraph a line on page 15 (20.7pt, the
  mark's) with the box on it, and the table after ran onto a 19th page.
  The reader now ends such a paragraph with its break on the page before,
  floats and all. zh-021b8feb 85.6 -> 93.8; nothing else moved. (Its 19th
  page is pages 16-18's own matter.)
- **A row with a turned cell parts at a page's foot like any other
  (2026-10-17).** zh-021b8feb's "職場人力協助" row has its first cell
  turned (tbRlV) and a merged continuation. Word's print parts it at
  page 17's foot. Ours kept every row with a turned cell whole, took it
  to page 18, and the table ran onto a 19th. zh-021b8feb 93.8 -> 98.6
  with Word's 18 pages; nothing went down. (The same sweep showed
  zh-701eda18 and zh-e0ca7252 rising too. That came from other sessions'
  commits pulled in by the rebase between s318 and s319 — 7a767c5c among
  them — not from this: with it alone reversed, both miss as many lines.)
- **A word wider than the line opens a line of its own after an ideograph
  too, in a cell of any width (2026-10-18).** zh-ff93733d's cell line
  "3. 線上關懷平台：http://df.ffceap.com.tw/taoyuantraining/" (a 210pt cell,
  the address a hyperlink) sets the address on a line of its own in
  Word's print, parted at the margin ("…/taoyua" / "ntraining/"). Ours
  parted it right after "：", the page after ran a line early, and so on to
  the end. The wide-word rule had asked a space before the word, a
  document not set by the East Asian rules, and a narrow cell. Now a word
  of twenty characters or more takes a line of its own after an
  ideograph or a full-width mark, in the body or a cell of any width.
  After a space the rule is as it was (under East Asian layout Word
  parts such a word where it stands: testABodyWordWiderThanTheLineOpensALine,
  which 8498b68f broke and the follow-up restores). zh-ff93733d 22.8 ->
  96.2; nothing else moved.
- **A geometric shape in a Times New Roman run keeps that face's line
  (2026-10-18).** zh-cec9d337's drill table has 22pt "○" cells (line at
  least 12, an 18pt grid, adjustLineHeightInTable). Word draws them in
  Times New Roman, which has the shape, and its rows are two pitches,
  36pt. The stand-in, Liberation Serif, has no "○", the platform's CJK
  fallback set each line 37.8, and every row stood 1.8pt tall until the
  table's last row went over the page. Such a shape (U+25A0–25FF) in a
  run whose Latin face is Times New Roman now asks a line of an em at
  most. Where Word's Latin face lacks the shape, Word too falls back to
  YaHei (zh-454e2e29's "○" and "△"), so the rule is for Times New Roman
  only. zh-cec9d337 71.8 -> 84.1; nothing else moved (s325 -> s326, one
  base, the change alone).
- **A turned cell parted over a page is shown across its whole cell
  (2026-10-18).** zh-264d7516's "被征地农户人员信息" (tbRlV, merged over
  nine rows, vAlign top) comes through the parted-row path since
  a0fcb76c. That path gave each paragraph a window of its own lines, a
  turned cell's one line of 34pt, and the label drew nowhere. Word's
  print has it down page 19, 156 to 256. Its window is now the cell's
  whole span: ours 157 to 257. zh-264d7516 93.6 -> 95.3; nothing else
  moved (s329 -> s330, one base, with starling-ios-5c's uncommitted
  skia-run-shift-once in the engine under both).
- **A Latin word's own curly quotes give nothing for it, before 2013's
  layout (2026-10-18).** zh-b00fef0d (mode 12, kinsoku off, 16pt
  仿宋_GB2312) ends a line "…执法。其中" and sends all of "“1”" to the
  next in Word's print. Ours took the word 29.4pt over, with 32 of room
  from four marks, two of them its own quotes. Lab `sq-q` (relayed by
  lenovo-2): with its quotes' room gone the word is not taken. Taking away
  all of a word's own marks broke ten documents (zh-6b242483 99.2 ->
  15.3), so only its curly quotes, only in the body, only before 2013's
  layout. zh-b00fef0d 96.4 -> 97.2; nothing else moved (s331 -> s333,
  one base).
- **A row's `w:gridBefore` columns stand empty before its first cell
  (2026-10-18).** zh-51af781b's scoring table (grid 5 | 840 | 7905 | …
  twips) opens each of its first 165 rows with a cell spanning 5 + 840.
  From row 165 on, its rows say `w:gridBefore 1` and start with an 840
  cell. The reader started every row's cells at column 0, so from there
  each number sat in the 5-twip column, one character a line, and each
  description in the number's 42pt. The table ran 17 pages to Word's 12,
  and the file 70 to 65. It is the corpus's only `w:gridBefore`, and the
  save writes it back with its `w:wBefore`. zh-51af781b 83.3 -> 83.6,
  pages 70 -> 65; nothing else moved (s335 -> s336). What is left of it
  is the reference: Word lays sections 5 and 6 (16850 x 11910 twips with
  no `w:orient`) out landscape and prints them on portrait paper, centred
  and clipped at both sides, so their first column reads ".3" for "1.3".
  And p57's "…不小于5m²,得1 分)" keeps "；" whole and drops ")" 12pt
  where ours squeezes the "；" to keep it; that row stands 11pt taller in
  Word, and p58-64 drift from it.
- **A paragraph of floating objects alone goes to the next page whole
  (2026-10-18).** zh-b24b396a's figures D2 and D3 are 36 drawing groups
  (dimension lines with arrowheads, turned text boxes) anchored in one
  empty paragraph that Word starts page 13 with, after page 12's four
  empty lines leave no room for its line. The painter's line of such a
  paragraph is its anchors', 0.82pt tall, while the paragraph stands an
  empty line, 14.64pt. The cut at 0.82pt fitted, and as a cut under the
  last line it left the rest behind as if it were space after. Its
  objects are drawn only with the paragraph's piece whole, so they were
  all lost, and page 13 showed the text boxes of the paragraphs after it
  and no lines. Now such a paragraph parts nowhere, as a picture's does.
  zh-b24b396a 82.0 -> 86.0; nothing else moved by it (s336 -> s337, with
  zh-5dc5ce34 20.3 -> 19.5, zh-701eda18 98.0 -> 98.4 and zh-8f9b19f4's 16
  -> 15 pages shown by a base build from the same sources to be the
  sweep's base, not this change). Left on that page: a few turned
  labels, and some box labels drawn twice.
- **Under `w:overflowPunct` off a paragraph's last mark gives its half
  (2026-10-18).** The `hang1`–`hang6` rule says that under a `zh-TW`
  `w:noLineBreaksBefore` list, before 2013's layout, a paragraph's final
  mark neither hangs nor gives. It holds where the mark might have hung.
  zh-749cb15a's style k4a turns hanging off, and its "(2)規劃…教育訓練
  活動。", 2.1pt over at 14.4pt a character, is one line in Word's print,
  the "。" set 12.3 wide. That is a cell's case (lab `pe`), where nothing
  hangs either. Ours sent "動。" down, and five runs of pages drifted a
  line. zh-749cb15a 87.2 -> 90.2; nothing else moved (s338 -> s339, one
  base).
- **A paragraph that takes itself off the grid keeps its Latin text on
  it (2026-10-18).** zh-c2f6d17a's body paragraphs say `w:snapToGrid` 0
  in their own `w:pPr`, on a grid of `linesAndChars` charSpace -849
  (-0.207pt at 16pt). Word's print sets their ideographs 15.8 apart, as
  ours did, and their Times digits 7.9: half the grid's addition off
  8.0, as on the grid. Ours set the digits at 8.0, so a justified line
  holding "120" and "48" was 0.8pt longer. It then left a character
  8.41 over that the line's "；" (7.9) plus that 0.8 let Word take, and
  from p21 every page stood a line behind. Not where a STYLE turns the
  grid off: tried for both, it cost zh-3c055c9b 91.7 -> 76.4 and
  zh-268f8d15's footer 98.8 -> 93.0, as recorded under
  `ideographGrid`. So `RichParagraphStyle.ownGridOff` marks the
  paragraph's own say. zh-c2f6d17a 54.9 -> 93.5, zh-8d6f702e 88.2 ->
  90.7; nothing else moved (s340 -> s342, one base).
- **Word for Mac widens a synthetic bold by a fixed share of the em
  (2026-10-18).** Lab `bw` (Word 16.113.3; regular and bold lines at 8
  to 32pt in zh-167ee06c's package) sets each bold character 0.0195 em
  wider in PMingLiU and SimSun and 0.0200 in JhengHei UI Light (the
  face 華康雅風體W3(P) is drawn in), at every size. Lab `sqf` first:
  zh-167ee06c's bold "七、經同意…為必要" leaves "要" for the next line in
  PMingLiU and in the original face alike, and takes it in both when
  set regular. So the face did not matter, and the bold did: at 14.28 a
  character the line is about 14pt over, more than its two marks give.
  JhengHei UI Light now emboldens at 1/50 (`boldWiden`). Its 18.5pt bold
  title, 22 characters at 18.87, ends 0.16pt inside its margin; 1/48 had
  wrapped it, and the title's "421pt" in the earlier note included its
  paragraph mark. The 1/48 of the faces already marked (FangSong's, set
  by zh-15428325) stays. zh-167ee06c 71.9 -> 87.2; nothing else moved
  (s343 -> s344, one base).
- **Word's Thai faces at Browallia New's widths (2026-10-18).**
  zh-6a4fc013 is a Chinese–Thai Q&A whose Thai sits in `<w:cs/>` runs
  of "TH Sarabun New". Word for Mac draws that, digits included, in
  Browallia New (embedded in its print, not on disk). Browallia's
  advances are Cordia New's (DFonts cordia.ttc) to half a per cent.
  Faces named for Word's Thai fonts now take Cordia's ASCII table. Their
  Thai, drawn by the platform's fallback, takes a character class of
  its own (4, `RichResolvedFace.characterClass`) scaled to Browallia's
  widths: 0.75 against Thonburi on a Mac, 0.729 against Leelawadee UI on
  Windows (Windows 01QbbApP). The fonts' own tables gave 0.549 on the
  Mac, but Thonburi's hmtx counts its marks, and 0.549 set 541 lines.
  Word's print gives 0.689 a glyph, which set 588; 0.75 sets Word's 614
  lines on its 26 pages. zh-6a4fc013 38.3 -> 54.2 (it had run 693 lines
  on 29 pages); nothing else moved (s346 -> s347; no other file names
  these faces). Linux keeps its fallback unscaled for now.
- **A no-break space after an ordinary one is the Latin text's
  (2026-10-18).** Lab `nb1` made a no-break space in a square face an
  em ("甲" + ten U+00A0 + "乙"). zh-f3802561's articles open "第一条"
  + U+00A0, U+0020, U+00A0, U+00A0 in a 10.5pt 仿宋 run, which Word's
  print sets 10.5, 5.25, 5.25, 5.25. The first follows an ideograph and
  is an em; those after the space are the space's half em, as a neutral
  character takes the script before it. 仿宋 has no U+00A0 of its own.
  Ours set all three an em, 10.5pt more an article, and the first line
  of each lost a character. zh-f3802561 69.4 -> 99.8; nothing else moved
  (s347 -> s348).
  The same holds after a Latin letter or digit (2026-10-23): zh-a7a889eb's
  "3.5" + U+00A0 + U+0020 in a 12pt 宋体 run hinted East Asian is 6 and 6
  in Word's print, and its line "3.5  拟派…专业 贰 级" took the last three
  characters ours left for the next. After a "." the no-break space stays
  an em — zh-17749c13's "1." + U+00A0 + "船" (its own run) is 14 at 14pt —
  so only a letter, a digit or a space before it makes it the Latin's.

- **Notes at the foot, counted once.** A body line's notes are set on
  the page with the line that marks them, and a later note of the same
  paragraph that has no room sends its own mark's line over — the page
  ends above that line. The cut is above the line itself, not above it
  less the room of the notes already taken on the page: `reserveNotes`
  takes that room off the foot right after, so counting it in the cut
  took it twice, and the line marking the earlier notes went over as
  well. zh-7a16a243's page 12 ends with the line marking notes 15 and
  16 in Word's print, note 17's line first on page 13; ours sent the
  15/16 line over too, and pages 13-26 ran a line behind — 66.3 to 85.2
  of Word's lines, the same-base pair moving no other document.
- **A continued paragraph's notes, likewise.** Where a paragraph goes
  on at a new page, the notes whose marks stand in its lines there are
  fitted by mark line as where it began — and one that no line of fits
  under its mark sends the mark's line over with it, the page ending
  above that line, as the body path does; it used to be deferred alone,
  the line kept. zh-7a16a243's "都市計畫法第32條34及第22條35規定…", the
  last line page 42 holds of a paragraph begun on page 41, opens page 43
  in Word's print with notes 34 and 35 at its foot; ours kept the line
  with 34 and set 35 first on 43, and pages 43-51 ran a line ahead —
  85.2 to 95.2, the same-base pair (n3/n4) moving no other document.
- **East Asian vertical text boxes.** A text box whose body says
  `vert="eaVert"` runs its text down as `vert` does, but an ideograph
  stands upright in it, with the vertical form of a mark ("︓", "︐"),
  while Latin text, digits and spaces lie on their sides, each where
  the line sets it. zh-c4f2be3b's landscape pages number themselves in
  such a box at the page's left, "- 33 -" reading down in Word's print,
  and zh-6d402586's side note "通知書一式兩聯：…(備註：…)" stands
  upright with its "(" turned. Ours had read no `eaVert` and set both
  across: zh-c4f2be3b 95.4 to 99.7, zh-6d402586 91.3 to 96.7,
  zh-2e7ef069 90.0 to 92.8, nothing else moved (pair n5/n6).
- **VML groups drawn.** A `v:group`'s shapes are drawn as a DrawingML
  group's are (`WriterGroups.registerVML`): `v:line` from its `from` to
  its `to` (a `flip` takes the ends across), boxes, ovals and shapes of
  a known type (`o:spt` as the preset it is: 109 a process, 117 a
  preparation, 202 a text box's rectangle…), connectors (32 straight,
  33 an elbow) and free paths (`m … l … c … x e`), each in the group's
  `coordorigin`/`coordsize` through every nested group; `stroked`,
  `filled`, `strokecolor`, `fillcolor`, `strokeweight` and the
  `v:stroke`/`v:fill` children; arrows (`startarrow`/`endarrow`) on
  lines and open paths only — Word draws none on a closed box whose
  stroke names one (zh-6e6b9821's side notes); WPS's turned connectors
  in 65536ths of a degree ("rotation:-5898240f"). A shape is a picture
  only where its `v:imagedata` names one: WPS writes an empty one into
  every shape, and zh-e9f256c1's whole flowchart was skipped as
  pictures. Before, a VML group printed its text alone. zh-6e6b9821,
  zh-e9f256c1 and zh-7773163d now draw their flowcharts as Word does,
  and WordWithAttachments its "Словарь" box; no line score moved (pair
  n7/n8). Dashes too (`v:stroke dashstyle` — "dash", "shortdash", a list
  such as "1 1" — and a DrawingML group's `a:prstDash`/`a:custDash`), cut
  by Slides' `SlidePainter.dashed`: zh-6e6b9821's dotted leaders and
  zh-2e7ef069's dashed stage frames as in Word's prints (pair n9/n10: no
  line score moved, drawings changed only in zh-2e7ef069). Then the
  leftovers: a picture inside a group (`v:imagedata` naming one, decoded
  once and drawn over its box — zh-7773163d's footer logo); a lone VML
  shape (`v:rect`, `v:roundrect`, `v:oval`, `v:shape`) as a group of
  itself, its edges and fill drawn (zh-7773163d p35's steps,
  zh-60c80728's whole incident flowchart); and a lone DrawingML line with
  an arrow at an end drawn by the group painter, not the plain outline,
  which has none (zh-2e7ef069 p9). Two traps on the way: a line's arrow
  ends follow its flips — a "flipH" line runs from its top right, so its
  tail is at the foot; ours put every rising line's tail at the top,
  which also reversed zh-ae2dd08d's existing arrows — and an upright or
  level line is `cx="0"` or `cy="0"`, which the group reader refused
  (zh-e2dc9dce's connectors vanished); a system colour (`a:sysClr`) is
  its `lastClr`. Pair n15/n16: no line score moved; in every changed
  document the segments added match Word's print (PyMuPDF, ±2.5pt).
- **A table style's header borders.** A table style's `firstRow` cell
  borders (`w:tblStylePr w:type="firstRow"`'s `w:tcBorders`) stand for the
  header row's unstated sides, as a row's `w:tblPrEx` does: zh-61aaad09's
  "浅色网格" style rules its header's foot 2.25pt, and Word gives each row
  either side of it half that — 29.6pt rows where the rest are 29, ours
  28.5 — and ended page 2 a line sooner. Not the foot of a header cell
  merged on down (its merge ends on the inside line in Word's print).
  56.8 -> 83.8, nothing else moved (pair n17/n18). The line itself is
  still painted at the table's 1pt.

### Word is not one reference: the fonts a Chinese document gets (2026-10-18)

What these files look like depends on which Word opens them, on which
machine, and sometimes on the session. Measured on the Mac (Word 16.113.3)
and the Windows box (Word for Windows, Windows 01QbbApP):

- **The machines have few of the faces the documents name.** Government
  documents are set in 仿宋_GB2312 (body), 方正小标宋 (title), 黑体 and
  楷体_GB2312 (headings) — the national format, GB/T 9704 — and in Taiwan
  in 新細明體 and 標楷體. Stock Windows has 宋体 and YaHei of these, and
  the 明體 pair; FangSong, KaiTi and SimHei are Office *cloud* fonts, fetched
  when a document asks for them; no `_GB2312` or 方正 face exists on either
  machine. Word for Mac carries 宋体, 黑体, 楷体, 仿宋 and the 明體 pair.
- **Each Word maps a missing name its own way.** For 仿宋_GB2312: where
  the file embeds the face (`word/fonts/`), both Words draw the embedded
  subset; where its font table gives `w:altName` 仿宋, Word for Windows
  draws FangSong and Word for Mac draws Microsoft YaHei (32 of the corpus's
  34 such files); with neither, both draw YaHei. Word for Mac does follow
  some alternates — 楷体 for 楷体_GB2312 (`OfficeFonts.eastAsianFace`).
- **The same face differs between them.** FangSong is a 1.000 em line in
  Office's cloud build 5.02 (Windows) and 1.141 in the Mac's: a line of
  仿宋 does not stand at the same height in the two Words.
- **The same Word differs between sessions.** Word for Mac sets some
  方正小标宋 runs in Arial Unicode MS (a 1.75 em line) in some sessions and
  in YaHei in others: reprinted on 2026-10-18, zh-1a3c7aa0 went from 90 to
  92 pages, zh-1563bd74's title from YaHei to Arial Unicode (starling-ios-5c);
  after a relaunch zh-5450d509's body printed in YaHei where its checked-in
  print has SimSun.
  A reference print can be off for one document while the rest of its batch
  holds — zh-167ee06c's was, and it was reprinted.
- **So the app has three sets of rules, `OFFICE_WORD_FONTS`.** `mac` is
  Word for Mac's fallbacks — YaHei for every name it lacks — and is what
  the corpus's references are printed with and every sweep runs under.
  The default is the author's faces: 仿宋 and its names in Starling
  FangSong, the 方正 titles at their own line, other missing names the
  square face they were made in. `windows` is Word for Windows' fallbacks
  on a stock machine — a missing name's font-table alternate where it
  has that face (仿宋 for 仿宋_GB2312 is its cloud FangSong), else YaHei —
  for comparing with its prints (Windows 01QbbApP, lab `fsw`: thirteen
  such prints, 64.5% of their lines under the default, 84.8 under
  `windows`).
- **Embedding is rare.** Of the 131 WPS-made files in the corpus, 125 name a
  方正 or `_GB2312` face and 7 embed any font. WPS treats 方正小标宋 as a
  members' cloud font; without it WPS draws another face too.

So a Chinese .docx does not fix its own look; the fixed copy is the PDF or
OFD it is published as. For this app that means two separate targets:
**scoring** reproduces one Word's choices — Word for Mac 16.113.3, whose
prints are `test/corpus/docx/word/`, under `OFFICE_WORD_FONTS=mac` — and
**display** aims at the author's intent, the named face's own metrics. A
bundled 仿宋 look-alike (朱雀仿宋, OFL, re-metricked to FangSong: Latin at
0.5 em, curly quotes 1 em, a 1.0 em line) would serve display; it covers
all 6,763 GB2312 hanzi and 99.98% of the corpus's 仿宋 text. Built as
Starling FangSong (f32d5151; Resources/fonts/README.md): page difference on
the 26 FangSong-heavy documents 7.32% -> 6.54%, line match unchanged.
- **On a character grid the character taken is its cell (2026-10-18;
  Windows).** Before 2013's layout the next character is taken where it
  ends no more than half the one before it past the margin; the test
  measured an ideograph by its em even on a grid narrower than that.
  zh-eb54d3b0 (mode 12, 16pt on a grid of -0.21) has Word take "级，" at
  the end of "…到2025年总体目标：一是产业规模升", "级" ending half "升"'s
  cell past the margin to the twip (7.897), the "。" and "：" before it
  and the "，" after giving their halves. Measured by its em it was 0.21
  over that, and every line to p2's paragraph end ran a character
  behind. zh-eb54d3b0 95.4 -> 96.8; nothing else moved.
- **A mark closed up on a character grid is half its cell (2026-10-18;
  Windows).** Where a closing mark meets the next mark ("》，", "）、",
  "，“") it gives half of itself; ours took half its em and left it the
  grid's whole addition. Labs `og3`/`og4` (Word for Windows,
  zh-eb54d3b0's package, 16pt, in ~/starling-doc-check/lab/og) set
  each pair 7.9 apart on the document's grid of -0.21 and 8.5 on one of
  +1: half the em and half the addition. zh-eb54d3b0's "…扶持政策》，助推茶"
  then left "产" 7.81 over half of "茶" (7.897), which took it; Word's
  is 7.91 over and goes down — in Word for Windows too, on and off the
  grid (lab `og2`). zh-eb54d3b0 96.8 -> 98.0; nothing else moved.
- **A space sets no line (2026-10-18; Windows).** Where a line holds
  anything else, its spaces and U+3000s take no part in its height or
  its baseline, whatever their face or size. Lab `el` (Word for
  Windows, zh-2f9463d6's package, 12pt Times beside 微软雅黑, in
  ~/starling-doc-check/lab/el): "AB　", "A　B", "　AB", and "AB" with
  four 20pt spaces after it or before "CD", set the line "AB" does, on
  a 15.6pt line grid (26.04) and off it (24.0); "AB测" sets YaHei's
  (39.2, 27.9). Ours let a YaHei U+3000 make the line two pitches, and
  zh-2f9463d6's table row "……　" stood 13pt taller than Word's, its
  pages 20-21 with it. Not a no-break space: that is what a glyph no
  face has is drawn as, and form_footnotes' "D - " + Symbol box line is
  Symbol's in Word's print (lab `ws`, 12.24 at 10pt, where Times'
  is 11.5) — its 11pt spaces had stood in for that.
  zh-2f9463d6 95.9 -> 99.9; nothing else moved (306 zh, 110 POI).
- **Over single spacing a bold run sets the line its regular text does
  (2026-10-18; Windows).** zh-86547e97 opens "第一条 为加强…" with a
  Strong run, YaHei bold for 仿宋_GB2312, 16pt at 1.5 lines: bold's line
  is 1.73 ems to the regular's 1.715, 41.5 to 41.16pt. Word's print
  sets the paragraph's lines 41.0-41.3 apart, the first with them. The
  paragraph also holds a 15pt run, so ours held it by its tallest
  stretch, the bold, which stands on line 1 alone; no strut, the
  engine's own proportional line, no baseline correction, and line 1
  13pt low. Stretches of one size within 1.5% of each other now count as
  one, held at the height most of the text has, where the paragraph is
  spaced over 1.2 lines. Not at single: bug59058's Times paragraphs with
  bold labels keep each line's tallest, as Word's print does (100 ->
  88.2 when the rule ran at every spacing).
  zh-86547e97 75.9 -> 99.5, zh-d746674a 81.9 -> 91.9; nothing else moved
  (366 zh, 110 POI).
- **The 方正 Song titles keep their own line (2026-10-19; Windows).**
  Outside `OFFICE_WORD_FONTS=mac` a name no machine has is taken for the
  square face its author had (1.3 ems); 方正小标宋 and 方正大标宋 are
  taller — FZXiaoBiaoSong's hhea 0.867 + 0.297 by Word's 1.3, as
  zh-e8d4c046 embeds it, 1.51 ems — and a 22pt title is three 15.6
  pitches, not two. zh-f59a76e9's empty 方正小标宋_GBK line under its p2
  title stood a pitch short and pp2-12 ran a line high: 76.4 -> 99.6
  against Word for Windows' print (lab `fsw`, ~/starling-doc-check/lab/fsw);
  zh-dc9cfa34 41.1 -> 51.6, zh-ec1b6f63 10.4 -> 13.2; the other ten of
  the thirteen as before. The Mac's rules set these names in YaHei and
  do not move (identical output).
- **A sized footer frame over the margin parts no row (2026-10-19;
  Windows).** Where the page's footer holds a frame of a stated width
  raised over its anchor (`w:w`, `w:y` below 0) and reaches above the
  bottom margin, Word parts no table row at that page's foot: the row
  goes to the next page whole and parts there only if it is taller
  than a page. zh-73534289's footer is such a page number (11907
  twips wide, y -2, 720 twips up over an 851 margin), and no row of its
  118-row table is parted in Word's print; ours parted them and pp28-33
  ran out of step. Labs `rw`/`rw2` (Word for Windows, its package): a
  fresh one-row table a page and a half tall skips page 1's 33 free
  lines; it parts on page 1 with the frame removed, auto-sized, at y 1,
  the footer 200 twips up or the margin at 1100 — not at 980, nor with
  the frame 3000 wide at y -2. The usual page number, an auto-sized
  frame at y 1 centred on the margin, parts its rows: taken for any
  footer frame the rule cost some forty documents. A row under nothing
  but repeated header rows counts as at the page's top.
  zh-73534289 82.7 -> 99.6; the corpus's five other sized, raised
  footer frames as before.
- **A row's part that goes over draws its top line at the page's head
  (2026-10-19; Windows).** Where a row parts over a page, its part on
  the next page is ruled across its top again, on the line a row opening
  that page would have; ours drew it a line's width lower, under the
  room it leaves for that line. Lab `sr` (Word for Windows,
  zh-291fcea7's package): a one-row table parted at page 1's foot draws
  its page-2 top rule at 56.88, as a table opening the page does (56.88);
  ours 57.45, now 56.95. zh-f43c9edf 71.0 -> 100; nothing else moved
  (446 zh, 110 POI). zh-291fcea7 itself stays: in that package our cell
  text stands 0.65pt lower under its row's top line than Word's, in
  every row (labs T1/T2), and its p3 table ends 0.85 low.
- **A justified paragraph keeps the spaces it opens with (2026-10-22;
  Windows).** Word sets them at their width and stretches the line
  elsewhere; ours held a run of spaces as no-break ones only beside East
  Asian text, so a run before "9." was the line's stretch and went to
  nothing. zh-b378d8c4's "    9.化工：…" (14pt, balanced widths) has its
  four spaces 7pt apiece in Word's print, "9" at 107.4; ours at 80.4,
  now 107.4. The line match reads heights only, so no score moved (466
  zh, 110 POI, same base). zh-b378d8c4's misses are elsewhere: p13's
  foot keeps a 22pt exact line ending 0.4pt past the 1985-twip margin,
  which Word sends on.

Measured, and built on 2026-10-14 (above): **`w:mirrorIndents`** (3 of the 679, two in
the sample — one of them 687 paragraphs of zh-06c46ba9). On an even
page the indents are as written. On an odd page Word sets the right
indent to the left one plus the first line's (less a hanging one's)
and the left indent to the right one (plus a hanging indent's
depth): `w:firstLine="612"` alone ends every line 30.6pt short of
the right margin, on pages 1 and 3 and not on 2 and 4. An indent
that depends on the page the paragraph lands on needs the layout to
run again after the pages are cut.

Still open from the automatic space's lab: from mode 15 on the
spaces give in a justified paragraph only, and by a rule not found
(one space gave its whole 4pt, two under 4 between them, four under
5); and Word kerns YaHei's letters (a pair of "C" 10.25pt apart at
16pt, where one is 10.7 wide), which this app does not.

Left, in the order the line match names them: tables (cell widths,
vertical alignment), cover pages and frames in the
body, `w:topLinePunct` inside a paragraph,
drawn lines and shapes (a red rule under a letterhead), and whatever
the next first-differing line turns out to be.

### Balloons in Word for Mac's own face; changes nested in moves (T72, 2026-10-17)

A file with no Balloon Text style prints its balloons in Times 9pt in
Word for Mac (Tika-792, comment), not Tahoma 8pt; where the style exists
its face labels comments as well as changes (WordWithAttachments' Tahoma,
testComment's 宋体), and a comment's text is in Comment Text's face, else
Normal's. A deletion inside `w:moveTo` still leaves its place marked
"Moved (insertion) [n]", listed before a deletion at the same spot; an
insertion inside `w:moveFrom` (typed, then moved away) prints nothing
but its formatting change. Both are kept on the run as
`RevisionMark.nested`.

### A cell's side line is no room over its row; "○" on the grid (2026-10-18)

zh-5251dd23's calendar rows, two exact 17pt lines under a 34.35pt "at least",
stood 36.6pt in ours and 34.8 in Word's print, and p17 and p19 missed most of
their lines. The difference was the 2.25pt line on the first cell's left and
the last one's right: ours gave a top or bottom side the cell does not name the
wider of the cell's own line and the table's, so 2.25pt went over the row. Lab
`cal` (Word 16, the file's own table copied whole): every row is 34.8 with the
line on the left or the right, inside or at the table's edge, the lined cell the
tallest or not, and 34.56 with no stated height at all. A top or bottom side the
cell leaves unnamed is now the table's line there; left and right keep the
wider of the two.

That rule had come from zh-cec9d337, whose rows stand taller in Word's print,
and taking it away dropped that document to 51%. Its rows are tall for another
reason: their tallest cells hold a 22pt Times "○" (atLeast 12pt) on an 18pt line
grid, which Word sets in two pitches. Lab `g44`: a row of them is its 28.3pt
"at least" at 14pt and 36.5 at 18 and 22pt. Ours kept the geometric shape's line to an
em after the grid had snapped it, so the line was 22pt at every size. On the grid
it now keeps the line the grid gives, and the one-em cap holds only off it.

Together, sweep n361 against n360 on one base: zh-5251dd23 89.2 → 96.8,
zh-e1b09977 65.4 → 81.4, zh-cec9d337 84.2 → 88.2, zh-20c1d74a 88.0 → 89.9,
and no document lower. Either change alone drops zh-cec9d337.

### A fitted box's Latin paragraph is one piece (2026-10-18)

zh-2e7ef069's page number is a `wrap="none"` + `spAutoFit` box sized by its
numberInDash result "- 1 -", 36pt wide, and on every two-digit page ours wrapped
the closing dash under "- 10". Word's print has "- 10 -" whole, running out of the
box. Lab `ft` (Word 16, the file's footer over 11 pages): whole on pages 10 and 11,
and still whole with numberInDash removed and "- " and " -" typed round a plain PAGE
field, so it is not the field result's joiners. The engine had also parted the
number between its digits, which `filled`'s word joiners cannot stop. A paragraph
in such a box with no East Asian character in it is now as wide as its whole line;
`ftD`'s "— 10 —", which Word parts before its em dash, keeps the old measure.
Sweep n363 vs n362, same base: zh-01071d556 98.2 → 100, zh-2e7ef069 87.5 → 89.0,
zh-0a56c942 93.1 → 93.5, none down.

### A floating table centred on its margin, and its offset on the next page (2026-10-18)

zh-0243e7fc's page 11 form is a floating table, tblpXSpec center on the margin,
tblpY 272 twips under text, 539pt wide in a 415pt column. Ours ignored the spec,
so the form stood at the margin with its first column's text at 115pt, where Word's
print has it at 54, standing out on both sides. And taken over from page 10, where
its first row did not fit, it started at page 11's top, 13pt above Word's. Now a
tblpXSpec of center or right against the margin or the column is the table's
alignment (page-relative specs still unread), and a text-anchored floating table
whose first row goes to the next page stands its tblpY down there too. Sweep n365
against n364 on one base: zh-0243e7fc 81.6 → 98.9, nothing else moved.

### …in Latin faces; with an East Asian one its spaces give half (2026-10-18, Mac)

Narrows the rule above. Lab `vf` (Word 16): zh-2e7ef069's footer over one section
numbered from 9, so its 宋体 box is sized by "- 9 -" (36pt), holds "- 10 -" to
"- 99 -" whole — 7pt over, its two 7pt spaces halved — and parts "- 100 -" at its
space, 14 over, the closing dash on a line under it. So "one piece" holds only for
a paragraph set in Latin faces alone (zh-01071d55's Times "- 10 -", 7 over, is
drawn whole and clipped at the box in Word's print). With any character in an East
Asian face — 宋体 runs, an em dash (Word sets zh-875759ff's in YaHei), a hinted
run — the paragraph stays whole only where its line, less half its inner spaces,
fits: zh-5a9a85c6's "— 11 —" (宋体 spaces) stands, zh-875759ff's "— 10 —" (Times
spaces, 3.5 to give against 7) parts before its closing dash. A closing space
hangs and gives nothing; a space beside a character set as East Asian gives
nothing (zh-a4b0f6ea's hinted "— 10 —" parts). The lab also finds VML boxes
(`mso-wrap-style:none` + `mso-fit-shape-to-text`) sized once, as DrawingML's: the
old "VML is fitted on every page" came from zh-5a9a85c6, whose odd-page numbers
stand at 481–530 for "— 1 —" and "— 11 —" alike — the squeeze, not a refit;
zh-9bcea239's VML "—10—" wraps its dash on every two-digit page with its fonts,
rPr or compatibility mode (11, 12, 15) changed. Ours lays a paragraph that stays
whole out past the box, the box as wide as on its first page.

### A one-column table that draws nothing is the body (2026-10-18)

zh-e9616b2b is all one table: one 9828-twip column, two rows, its only line an
insideV (which one column never draws), and its three tables nested in the cells.
Nested tables flatten (a long one does not part across pages as a block), so its
35-row checklist ran as a column of cell paragraphs over four pages where Word's
print sets it over two, and the document had 10 pages to Word's 6. A table with no
style, no float, no shading, one grid column and one cell a row, drawing no line,
and holding tables of its own is now read as the body it frames. The wrapper is
kept and written back as it was while its text is (the `kc` path the column
sections use), so a save still has it. Only one corpus file qualifies: drawing.docx's
unbordered wrappers hold no qualifying shape and did not move. Sweep n367 against
n366 on one base: zh-e9616b2b 63.1 → 93.8 (pages 6/6), nothing else moved.

### A paragraph of spaces alone is one line (2026-10-18)

zh-cfb32050's scoring form opens with a row whose first cell is 14pt wide and holds
fifteen spaces under a 31-character first-line indent. A line narrower than an em is
laid out a character a line (see `_span`), so the spaces took six lines and the row
stood 216pt; Word's print has it as tall as the text cell beside it, 189pt, and the
form ran 27pt low on every page after. A paragraph of nothing but spaces is now laid
out as wide as its spaces, one line: they hang past the edge as a line's last spaces
do. Sweep n370 against n369 on one base: zh-cfb32050 76.5 → 98.1, nothing else moved.

### A digit inside a number is not a word of its own (2026-10-19)

zh-0a56c942's "…本科专业目录（2012年）" (wordWrap 0, mode 14, Times 16pt, justified)
ends "（20" in Word's print; ours took the "1" too, 7.8pt over, its "《" and "（"
giving 16. Without word wrap the fitter weighs the number a digit at a time, and
the one-Latin-character rule (labs `lw`–`lw4`: a word of one letter or digit is
taken whenever it starts inside the margin) took each digit as such a word. A piece
that goes on from a Latin letter or digit is now a longer word's, held to the start
rule. Sweep n373 against n372 on one base: zh-0a56c942 93.5 → 95.7, nothing else.

### A list level with no indents numbers at the paragraph's own left (2026-10-19)

zh-9ba2ead7's table cells number "1、" from a level that states no indents, no
suffix, and paragraphs that state none either. Word's print sets the number at the
cell's text edge with the text straight after it; ours, finding no left anywhere,
gave the item the editor's own list slot, which hangs the number out of the text,
23pt left of Word's, and every such cell's lines broke two characters late.
`_wordList` now falls back to the paragraph's own left for any list the file
defines (the first line its own, none here). Sweep n376 against n375 on one base:
zh-9ba2ead7 73.0 → 91.3, zh-27fc8f9d 96.4 → 97.6, nothing lower.


- **Repeated inline placeholder controls use one cached value (2026-10-21).**
  Word's `55966` prints the first `w:showingPlcHdr` inline text control's
  value in the next control naming the same `w:placeholder/w:docPart`.
  The importer previously read each stale `w:sdtContent` independently,
  adding a line and moving the final paragraph down. Word-for-Mac labs
  in `/tmp/starling-poi-fixes/placeholder` confirm reuse across paragraphs,
  while removing `showingPlcHdr` or changing the placeholder name preserves
  independent text. The reader now shares cached plain-text inline values
  within a document. Filled controls and unnamed controls do not participate;
  block-control refresh and rich controls remain outside this change.
  Same-engine, same-font sweep: 55966 33.3 -> 100%; all 576 other documents
  unchanged. POI mean 89.8 -> 90.4% including nine textless references;
  98/111 now at least 95%, all page counts still match.

- **Drawing positions inside compatibility markup (2026-10-21).**
  A `wp:anchor` can put `wp:positionH` or `wp:positionV` inside
  `mc:AlternateContent`: a wp14 percentage position in Choice, and an
  ordinary EMU position in Fallback. The reader now takes that fallback
  when no direct position is present. 60316's sidebar moves from the body
  column (x 238pt, overlapping its paragraphs) to x 36pt at the page's
  left. Its line match is 97.0 -> 100%; all other 576 reference documents
  unchanged. Visual comparison still finds its header divider too short:
  percentage size `wp14:sizeRelV` and header vertical alignment are not
  handled by this position-reading fix. Regression tests cover both axes
  and precedence of a direct position over alternate content.

- **RTL runs draw their complex-script font (2026-10-21).**
  `RichTextTheme.textStyle` now selects `CharStyle.complexFontFamily`
  for explicitly right-to-left runs, inherited from their named style or
  Normal, through `complexFaceResolver`. Latin runs keep their Latin
  resolver. Office preserves the requested or embedded complex face and
  supplies Cambria/Caladea, Times New Roman, Noto Naskh Arabic and DejaVu
  Sans as fallbacks. Word-for-Mac labs (`/tmp/starling-poi-fixes/rtl/lab`)
  show that a missing complex-script face uses Cambria for punctuation
  and spaces, and Times for Arabic. Using Times for both makes eight
  lines instead of seven. With the correct fallback order, rtl.docx has
  Word's seven lines and readable PDF text; the previous fallback was
  Geeza Pro with null text and nine lines. Native editor, layout dump and
  PDF export share the same resolver. Available fonts still determine
  fallback coverage on each platform; this sweep is on macOS.
  The matcher separately handles visual/logical RTL edge order and stops
  treating null Arabic text as matching letters. Re-evaluating the old
  corpus changes only rtl (71.4 -> 0). Against that corrected baseline,
  the three fixes move 55966, 60316 and rtl to 100%; all 574 other scores
  are unchanged. Final POI mean 90.7% including nine textless references,
  98.7% over 102 text-bearing files; 99 at least 95%, 111 page counts match.

- **Office resources load under Xcode SwiftPM and XCTest (2026-10-21).**
  Resource lookup now also checks the bundle containing the Office module,
  not only Bundle.main (Xcode's runner during tests), and reads fonts from
  `Bundle.resourceURL`. That covers Xcode's Contents/Resources layout and
  the native backend's flat bundle without a symlink. Repeated registration
  reports the original result instead of claiming success after a failed
  load. An early integration test requires the shipped faces before layout
  tests. All 444 Office tests now pass: the old 1.18-versus-1.15 line-height
  failure was the system fallback caused by a missing font bundle. The bare
  release converter also loads its fonts without the staging workaround.

- **Tracked-field balloon ordering: Word labs, still open (2026-10-21).**
  Reprinting delins reproduces the checked-in reference's order exactly.
  Isolating either paragraph 14 (changed mark) or 16 (unchanged mark)
  puts the field-code balloon after both formatting balloons. Removing
  the isolated paragraph's mark change does not change that order.
  Removing all mark changes from the complete document does change the
  first three fields' order; keeping only its link paragraphs also changes
  ordering, whereas retaining the preceding heading restores the original
  pattern. A paragraph's own mark alone therefore does not decide the order.
  Labs and Word PDFs: `/tmp/starling-poi-fixes/balloons`. No ordering
  workaround was added; the same 23 formatting and ten field-code balloons
  are present in both outputs, but their placement still differs.

- **A shape sized as a share of the page, aligned on it (2026-10-22, T143).**
  60316's header divider is a `prst="line"` connector whose height is
  `wp14:sizeRelV` 105% of the margins, placed `wp:align center` from the
  page, coloured `schemeClr accent2`. Ours drew its 99pt fallback extent
  from the header's top in black. Word's print: x 208.1, y 36.9..753.3,
  grey. The rule that fits it exactly: the box with its bottom effect
  extent (1.8pt) takes the share — 1.05 x 684 = 718.2 — and that whole is
  centred on the page, so the line is 716.4 long from 36.9. Built:
  `ImageFloat.heightShare`/`heightFrom`, top/centre/bottom alignment from
  the page or margins (header, footer and body), and theme colours for
  a line or box outline. A box that fits its text (`a:spAutoFit`) keeps
  its text's height: zh-3ecd3152, zh-8fa6164c and zh-e0ca7252 carry a
  stock 20% and are 28.5-48pt in Word's print (the first build grew them
  to 142pt). Paired sweep n379/n380: no score down, zh-06c46ba9 97.9 ->
  98.0 (its p71 box from y228 to Word's 72); shapes that moved, 60316,
  zh-06c46ba9 and zh-01071d55, now stand where Word's do.

- **A right-aligned line's trailing-space joiner has height only where the spaces wrap (2026-10-23).**
  `roomyTrail`'s U+2060 after a right-aligned paragraph's closing spaces
  makes the engine part them rather than hang them; its style was the
  first of [the ideographs', the Latin] that added under half a point to
  the line. On the Mac neither adds nothing — the joiner falls back to a
  face of its own: 0.78pt in the ideographs' style, 0.39 in the Latin —
  so zh-6e653ca0's and zh-e2dc2598's footer, "X隆阳区人民政府发布" and six
  spaces on one line in Word's print (bold 宋体 14pt), stood 18.6 where
  Word's is 18.2, and p8's "第四章" heading went to p9. zh-c5b5087b's same
  footer, whose spaces run past the line and end on a line of their own
  in Word's print as in ours, needs that height for the spaces' line
  (held to 0.05pt, or U+FEFF, or a pinned height, it lost it: 53.0 ->
  43.4; Linux's ideographs add nothing and never showed either). Now the
  paragraph is probed at the line's width: where its last character ends
  inside, the joiner is set at no height; where past, as before. Paired
  sweep n395 vs n394: zh-6e653ca0 and zh-e2dc2598 53.6 -> 100, zh-ae79c618
  88.4 -> 99.2, nothing down.

- **A merged cell over a parted row is centred in the row's whole part (2026-10-23).**
  zh-17ac8aa2 (sample 28, 75.0): its "所需信息情况", a vMerge'd label of eleven
  26pt lines centred over rows 7-9, stood 6.7pt high. Row 9 parts at page
  1's foot, and the label is centred in rows 7-8 plus what row 9 keeps on
  the page (`partingKept`). For a centred cell, that took the block from
  each paragraph to the column's end, not from the column's first paragraph.
  So "获取信息的方式（可多选）", three paragraphs of which two fit, read from its
  second as a two-line block that fits: 52.5 kept, where the cut (and
  `splitRow`'s part, and Word's print) is 65.7. Now the block starts at
  the column's first paragraph. Paired sweep n397 vs n396: zh-17ac8aa2 75.0
  -> 96.9, zh-540dc149 97.0 -> 97.8, nothing down (zh, POI).

- **A line's baseline is its tallest East Asian run's (2026-10-23).**
  zh-17ac8aa2's last miss: p2's "□若本机关…", a 黑体 "□" before 楷体_GB2312
  text on a 15.6pt line grid. The □'s face is one pitch tall, the 楷体's
  (Arial Unicode MS on the Mac) two, and the line two; Word centres the text
  in the two-pitch line (baseline 20.4 down), and ours stood it at the □'s
  one-pitch baseline (13.3). A line led by East Asian text took its baseline
  from the first East Asian run; it now takes the deepest of the first
  line's East Asian runs, as a Latin-led line already did of its runs.
  Paired sweep n399 vs n398: zh-17ac8aa2 96.9 -> 100, zh-21421b7d 97.4 ->
  100, zh-e02b0479 97.1 -> 100, zh-cd8987db 89.9 -> 90.3, zh-0a56c942 95.7
  -> 96.1, nothing down (zh, POI).

- **A section's columns, set as a row, may leave their space after past the foot (2026-10-23).**
  zh-8f9b19f4 ends in a continuous three-column section, "填报人：" |
  "审核人：" | "负责人：" (14.5pt, line 184-219 auto, 8pt after from the
  styles' missing pPrDefault), 31.4pt over the foot of a landscape page
  with no bottom margin. The reader sets section columns as a one-row
  table, and that row's 33.3 parted, columns 2-3 going to a page 15. Its
  lines end 25.3 down, and the rest is the last paragraphs' space after,
  which Word lets stand past the foot as it does for any body paragraph.
  The emulated table is now marked (`TableStyle.sectionColumns`), and its
  row fits where each column without its last paragraph's space after
  does. Paired sweep n401 vs n400: zh-8f9b19f4 15 -> 14 pages (Word's), 92.3
  unchanged (the scorer reads the moved lines as matched on neither
  page), nothing else moved.

- **A ")" after an ideograph hangs before Word 2013's layout too (2026-10-23).**
  zh-28416dc9 (sample 29, 78.9; mode 12, doNotCompress, 標楷體 14pt
  zh-TW, left-set) has "…委外機構(公 司)所在地…": Word's print ends the line
  "(公 司)", "司" inside the margin and the half-width ")" 4.8pt past it.
  Ours broke at the space before "司", and the page ran a line late. A
  Latin ")" or "," hung only from 2013's layout (zh-e0ca7252, zh-4b8e0abc).
  Now a ")" after an East Asian character hangs in the older layouts too
  (the comma, unmeasured there, does not). Paired sweep n403 vs n402:
  zh-28416dc9 78.9 -> 100, nothing else moved (zh, POI).

- **An empty paragraph that only ends a section stays on a full page (2026-10-23).**
  zh-12c4f07a's contents (section 2, 56.7pt margins) fill page 2 to its
  last empty line; the empty paragraph that carries their sectPr, which
  takes no room, was then sent to page 3 by the full-page check, and page 3
  — opened at it — took section 2's margins and header place, where Word's
  page 3 has the next section's 90pt margins. Such a paragraph no longer
  triggers that page; the next section's own break opens page 3 at its
  first paragraph. (Taking the next section's setup for any page opened at
  such a paragraph was wrong: zh-7488a70f's blank page 2, opened by the
  break itself, is section 1's in Word — no folio, the next page "1" — and
  zh-1a3c7aa0, numbered from 1 per section under even/odd headers, gained a
  blank page, 100 -> 29.3.) Paired sweep n409 vs n408: zh-12c4f07a 81.6 ->
  82.6, zh-f47b8a74 69.0 -> 70.7, nothing down.

- **A list over a numbering style's link takes that style's levels (2026-10-23).**
  zh-12c4f07a's "3.1.1" items (p10 on) are numId 32, whose abstractNum
  says only `w:numStyleLink` "7" — the levels are in the abstractNum that
  carries `w:styleLink` "7" ("%1.%2.%3"). The reader found no levels and
  drew bullets. A definition with no levels of its own and a numStyleLink
  now reads the linked definition's, and shares its counter. Paired sweep
  n411 vs n410: zh-12c4f07a +1 line (its next miss is a line fit on the
  same page), nothing else moved.

- **A number of Latin characters alone is set at its face's advances (2026-10-23).**
  zh-12c4f07a's "3.3.1.1." (its level's 14pt 標楷體, YaHei in Word's print:
  0.586 em a digit, 0.241 a stop) ends 93.0pt from the margin, under the
  96pt default stop (`doNotUseIndentAsNumberingTabStop`), and Word starts
  its text there. The marker set the face's advances on its Latin
  characters only where the number also held East Asian ones; "3.3.1.1."
  kept the stand-in's widths, ended 3.7pt later, past the stop, and its
  text went to the indent, 7.45pt on — a character a line fewer. Now any
  Latin character of a number takes them. Paired sweep n413 vs n412:
  zh-12c4f07a 82.6 -> 83.7, nothing else moved.

- **A picture taller than its exact line stands on the line, rising over the lines above (2026-10-23).**
  zh-ae2dd08d's flowcharts (sample 30) are inline groups — 446.9 x 594.4pt
  — in the last paragraph of a merged cell of exact 23pt lines. Word's
  print keeps that line 23pt and draws the group up the cell from the
  line's baseline, whole, so the cell's four rows stand at the 598pt its
  26 lines make. Ours grew the line to the picture: the last row was 656pt
  where Word's is 85, it went over the page, and the chart with it. Now an
  inline picture (a group with text too, not a nested table's box) in an
  exact line keeps the line and is drawn from the baseline up. Paired sweep
  n415 vs n414: zh-ae2dd08d 24.8 -> 47.2, 97 -> 96 pages (Word 94), nothing
  else moved. Left there: the groups' shape outlines are not drawn.

- **East Asian single-spaced lines with a bold run are held to the paragraph's common height (2026-10-23).**
  zh-ae2dd08d's "(一) 一般對象（補助80%…" (YaHei for 標楷體, 12pt, single)
  has a bold run on its third line. The bold's line (1.73 em) differs
  from the regular's (1.715), so the paragraph had no strut, and its first
  line, where "80%" is drawn by YaHei's Latin stand-in (a sans 1.07 the
  size), took the stand-in's own split about the baseline: 21.5pt where
  Word's is 20.4. Every numbered paragraph stood a point low, and page 37
  lost its last line. The strut that holds a paragraph to the height most
  of its text has, beside a bold run (`_strut(near:)`, until now only over
  1.2 lines), now applies at single spacing in documents of East Asian
  layout too. Paired sweep n417 vs n416: zh-ae2dd08d 47.2 -> 49.9,
  nothing else moved.

- **A VML shape behind the text wraps no text (2026-10-23).**
  zh-6d402586's annex is a section of one empty paragraph anchoring a
  786pt flowchart picture (VML, wrap "tight", z-index -251652097) on a
  page whose body is 770. Word prints it on that page; ours wrapped the
  paragraph's own line under the picture, past the foot, and left a blank
  page. A VML shape with a negative z-index now wraps nothing beside it;
  a top-and-bottom one still takes its band (zh-7773163d's 153pt boxes,
  which a first version that cleared that too cost 0.8). Paired sweep n421
  vs n420: zh-6d402586 39.3 -> 62.2, 41 -> 40 pages (Word 39), nothing
  else moved.

- **A picture's paragraph taller than its page goes whole onto it (2026-10-23).**
  zh-6d402586's "參考資料1" is a paragraph of a text box anchor and a 749pt
  inline picture on a page of 698. Word prints it on page 26, overfull, its
  section break with it, and "參考資料2" on page 27. Ours placed the picture
  as "a line taller than a page", carried the 9pt under it to a page 27 of
  its own, and the next section opened page 28. A paragraph of objects alone
  now goes whole onto the page it starts, which it leaves full; the empty
  section mark after it takes no room there (the `ender` rule). Paired sweep
  n425 vs n424: zh-6d402586 62.2 -> 90.9, 39 pages (Word's), nothing else
  moved.

- **REVERTED (2026-10-23, the user's decision): the entry below fitted a Word for Mac fault.**
  Since 2026-10-18 Word for Mac on the printing Mac draws any EMBEDDED face
  as blank one-em glyphs; Word for Windows draws the real face (windows-1's
  print of zh-529fa492, digits half an em), as this Mac did before. The user
  chose real Word, so the em-a-glyph override is gone: the face keeps its
  own widths. Paired sweep n423 vs n422: zh-a031fa16 89.0 -> 55.9 against
  its Mac reference, which is one of the ten set aside on the board;
  nothing else moved.

- **An embedded SimSun with bitmaps, under another face's name, is an em a glyph (2026-10-23).**
  zh-a031fa16 (sample 26, 55.9) embeds as 仿宋_GB2312 a file that is
  SimSun (its `name` table says so), with Windows' bitmaps (`EBDT`), and
  Word for Mac draws it — "Helvetica" in its PDF, no text map — with
  every glyph an em, ASCII too, and bold no wider: "2024" 18.0 apiece in
  the 18pt bold title and 14.0 in the 14pt body. Ours drew the embedded
  face at its own advances (digits half an em, bold 1/48 wider), and its
  lines held four characters more. Lab `emb` (Word 16, this package): the
  embed dropped, Word falls back to YaHei; the runs and the font table
  renamed SimSun, the same file is drawn as SimSun, digits half an em,
  bold 18.4 — line for line as ours. Only with bitmaps: zh-2bca0bdf's
  楷体_GB2312 and zh-e8d4c046's 仿宋_GB2312, SimSun without `EBDT`, print as
  SimSun (the first try, every misnamed SimSun, cost zh-2bca0bdf 97.6 ->
  60.1); zh-c2f6d17a's bitmap SimSun as 楷体_GB2312 is "Helvetica" in its
  print too. `loadEmbedded` now notes each face's own family and its
  `EBDT`, and `eastAsianFace` gives such a face 1-em ASCII advances and no
  bold widening. Paired sweep n393 vs n392: zh-a031fa16 55.9 -> 89.0,
  nothing else moved.

- **An autofit column a hair too narrow is widened; a wide "29-30" parts after its hyphen (2026-10-22).**
  zh-fea6e23a (sample 25, 54.7): its schedule's time columns are 46.8pt,
  36.0 of text, and "11:30-" needs 36.23. Word widens both to 47.0 and
  takes the 0.2 from their neighbours (its print's rules: 230.2/277.2/
  379.0/426.0); `_autofit` refitted only a cell a whole point over, so the
  grid stood and the line parted "11:30" / "-" / "13:00", three lines a
  cell. Lab `hy` (Word 16, this package, fixed one-cell tables at 36.23 to
  32.23pt) sets "11:30-" whole only at 36.23, as ours: no hyphen hangs in
  a cell, so the column is the difference. The tolerance is now 0.05pt.
  That exposed zh-e329b438 (85.1 -> 54.3 alone): its 14pt score ranges
  "29-30" measured one piece, 49.7 against a 49.1 column, where Word
  prints "29-" / "30" in a column of 48.9. `_wideWordHyphens` and the
  autofit pieces parted after a hyphen before a digit only in a time
  (a colon in the word), for zh-64044a1d's phone numbers (mode 11,
  compressing); from 2013's layout, or where nothing is compressed, any
  such word now parts there, as `_fittingWordHyphens` already allows for
  one that fits. Paired sweep n390 vs n388: zh-fea6e23a and zh-b3e887f7
  54.7 -> 100, zh-e329b438 85.1 -> 89.7, zh-7dd5643e 88.2 -> 90.0,
  nothing down; zh-64044a1d 98.3 unchanged. Left in zh-e329b438: its
  label column is 28.0 in Word's print and 31.6 in ours.

- **A form check box is drawn as Word draws it (2026-10-22, T143h).**
  The reader turns a FORMCHECKBOX field into "☐" or "☒" and the writer
  saves those as the field; Word's print draws the field as a square,
  not a glyph — at 10pt a 9.36pt box stroked 0.72, with 1.06 before and
  1.08 after it (an 11.5pt advance, against Apple Symbols' 8.3–8.96), its
  foot 0.96 under the baseline. Under Word's rules the layout now keeps the
  character, hidden, and sets after it a placeholder of that advance and a
  zero-width space in the run's style (a cell of one box keeps a line of
  text's height: Word's are 11.52 at 10pt, the box alone 9.36). The
  painter strokes the square, crossed for "☒". After the character so a
  tab before it sets the box at its stop: placed before it, the tab put
  the hidden character at the stop and the box 11.5pt short. A one-run
  paragraph skips the fast path when it has one. The text layer keeps no
  "☐", as Word's has none. form_footnotes: all 29 boxes within 0.2pt of
  Word's x, "Yes" 3.2pt nearer Word's; the corpus's only other check boxes
  are in checkboxes.docx. Paired sweep n386 vs n385: form_footnotes 97.7 ->
  98.9, nothing else moved.

- **A row taller than a page ends at the foot; a wrapper keeps its cell's room (2026-10-22).**
  zh-045c5a75 (sample 23) was a page long at 24.9%. Its row of at least
  779.75pt (`trHeight` 15595, more than the page's 749.7pt) runs over pages
  4 to 7; every continuation was made at least the stated height, so the
  last part, whose text fits page 7, was padded past the foot and parted
  again into an empty page 8. A continuation whose text fits is now no
  taller than the room to the foot (zh-b378d8c4's 132pt row, which does
  fit, keeps its stated height as before). Second, its 社會救助法 text is a
  table inside an invisible one-column wrapper (`_isInvisibleWrapper`),
  which the reader treats as the body. That dropped the wrapper's 0.75pt
  cell margins and spacing, and Word sets the first line 2.35pt lower; the
  row at page 9's foot then kept a line Word sends over. The wrapper's cells
  now keep margin + spacing (twice on the first and last rows) as their
  first and last paragraphs' space, as flattened nested tables already
  do. Paired sweep n382 vs n381: zh-045c5a75 24.9 -> 58.7, 37/37 pages;
  nothing else moved (zh, POI). Left there: in-line punctuation squeeze in
  its zh-TW cells (mode 14). Word squeezes "、" and the final "。" together
  on some lines and refuses "…生活扶助。" 10.9pt over with both able to
  give 6.5; not yet explained.

- **A positional tab goes to its place on the margins (2026-10-22, T143).**
  `w:ptab` (alignment left/center/right, relative to the margin) was a
  plain tab, which the Header and Footer styles' centre and right stops
  happened to place in seven POI files. bug57031's footer, "VDPAM
  527_S. Azeem_HW13 <right ptab> Page 2 of 14", has the ptab as its first
  tab, so the text centred on the 234pt stop (x 281) where Word's print
  ends it at the margin (x 490). The reader now records each ptab by its
  count among the paragraph's tabs (`positionalTabs`), and the tab layout
  sends it to the column's left, middle or right past any stops between.
  bug57031's footer is at x 490.0 on every page, as Word's; the seven
  other ptab files (ThreeColHeadFoot and kin) are unchanged to 0.1pt.
  Sweep n378 against n377: every score and page count unchanged (x is
  not scored). Saved, a ptab still writes back as `w:tab`, as before.

- **Short cells align within a split row's kept lines (2026-10-21).**
  A longer centred cell may have its initial cut moved to its text's top
  before splitting. That does not make it a continuation part. Testing
  every cut against the row's top skipped the adjustment of its shorter
  neighbours, centring them down to the page foot instead of in the kept
  lines. Use the actual first-part flag. Word labs with one-, two- and
  five-line cells keep one line from each: centre and bottom alignment
  both put the short cell on that line. Before: 5.8/11.6pt low; after:
  baselines 524.46pt against Word's 524.40. Regression test fails before
  the change and passes after it. Full 577-document sweep: bug65649 now
  matches all 6,674 reference lines (four misses fixed); 14 Chinese
  documents improve, none regress. All 111 POI physical page counts still
  match. All 445 Office tests and repository lint pass. Artifacts:
  `/tmp/starling-poi-fixes/split-cell`; comparisons in `sweep/comparison.json`.

- **Textless POI files need image checks (2026-10-21).**
  51921-Word-Crash067, 59378 and Bug62859 are blank in both PDFs.
  headerPic and zero-length have the expected header images. The
  issue_51265 samples have small horizontal offsets; issue_51265_3 also
  pushes its body pictures down: y213.31 vs Word121.40. Removing the last
  tab from its header in a lab reduces Writer's first body picture to
  y124.40; removing all header tabs gives y121.51. The header's trailing
  tab creates extra reserved height, and its other tabs shift the header
  pictures about 28–30pt right. No fix yet. TestTableColumns also needs
  border/position work. These nine samples remain N/A for line matching,
  not 100% successes. PDFs/contact sheet: `/tmp/starling-poi-fixes`,
  tab-isolation labs: `picture-header`.


- **Picture-only tab rows use spacing boxes (2026-10-22).**
  `issue_51265_3` has three header pictures at left, centre and right tab
  stops, then a final tab. Letter-spacing the tabs shifted the entire
  picture line about 28–30pt right. A separate trailing-tab workaround
  added another picture-height line even though the engine reported one
  line; text descent under the tabs added more height. Word prints the
  original and a lab with its final tab removed identically.
  For rows containing only inline pictures with image data and tabs, tabs occupy
  zero-height placeholders; trailing gaps end at the margin, and the
  extra-line workaround does not apply. Image painting maps each picture
  to its actual placeholder, including when paragraphs are inserted or
  removed. The first body picture moves from y213.31 to y121.55, against
  Word121.40; all seven pictures remain visible. Small horizontal offsets
  remain because inline left/right effect extents are not yet read.
  Opaque objects keep text-tab metrics: applying the same change to
  zh-7773163d's legacy VML arrow rows lost their descent and moved the
  following text boxes up 3–7pt. The full sweep caught that regression.
  Labs and PDFs: `/tmp/starling-poi-fixes/picture-header`.
  Validation: 448 Office tests and repository lint pass. All 577 line
  scores and physical page counts are unchanged from split-cell/sweep;
  image-box comparison changes only issue_51265_3 and keeps all seven
  images. The Chinese VML document's PDFKit text rows are identical to
  baseline. Final sweep: `picture-header/sweep-scoped`; the earlier
  `picture-header/sweep` records the rejected broader change.

- **Inline pictures reserve their left and right effect extents (2026-10-22).**
  Writer already read `wp:effectExtent` above and below pictures, but
  dropped its left/right values. `issue_51265_1/2/3` therefore placed
  pictures 1.5pt too far left; adjacent pictures accumulated that error.
  Word labs with horizontal extents zeroed confirm the rule: the first
  picture shifts by its left extent, a centred picture by half of left
  minus right, and a right-aligned picture by its right extent. Both
  sides contribute to the width that the line and tab stops reserve.
  The reader now retains both values for inline pictures and objects;
  standalone and inline layout include them, and painting insets the
  picture by the corresponding side. A character border encloses the
  effects: the frame-effects Word lab adds 12pt left and 6pt right,
  moving the picture 12pt and widening the frame by 18pt. Resized
  pictures drop their old spacing, floating placement stays unchanged,
  and the original values survive a DOCX save through the kept markup.
  Direct PDF checks retain all 1/2/7 images in the three POI documents;
  maximum image-coordinate errors against Word are 0.05/0.11/0.36pt.
  The two border labs match frame bounds within 0.25pt. Artifacts:
  `/tmp/starling-poi-fixes/picture-effects`, including measurements.json
  and frame-measurements.json. Alignment, adjacent pictures, resizing
  and DOCX round trip are covered by tests.
  Validation: all 451 Office tests and repository lint pass. Full
  577-document sweep: every line score, physical page count and image
  count is unchanged against picture-header/sweep-scoped. Thirteen files
  have adjusted picture boxes; see image-comparison.json and
  changed-image-word-comparison.json. POI text-bearing mean stays 98.7%.
  This is not a claim that every picture moved closer to Word: drawing
  page 9's right-aligned 161.25pt banner has no effects of its own, but
  moves with its containing percentage table. Its right-edge error grows
  3.90 ->5.40pt when the neighbouring picture's 1.5pt left extent enters
  the table's minimum-content width. Word's zero-horizontal-effects lab
  keeps that banner at x391.55/right552.80; Writer still expands this
  overfull nested table. Keep the verified picture extent rule and track
  the table-width/overflow rule separately; do not call the result free
  of visual regressions. Other existing page-9 gaps include transparent
  spacer pictures and vertical offsets. The zero-effects lab also changes
  earlier pagination geometry, so its y positions are not used as a new
  reference. Initial sweep ran out of disk; redundant intermediate PDFs
  were removed and the final sweep regenerated all 577 successfully.

- **A fixed parent constrains its nested table (2026-10-22, T142).**
  Word labs in `/tmp/starling-poi-fixes/nested-table` isolate the page-9
  drawing banner from its larger document. A separate confirmed rule:
  a 200pt nested table in a fixed parent keeps its preferred width when
  it contains a 240pt picture with 1.5pt left effect spacing. The picture
  overflows; it does not widen the nested table to 241.5pt. The same
  applies to a long text word. A 100% nested table uses its parent's
  available cell width (200 or 300pt), and 42.74% of a 200pt parent is
  85.5pt, even when the saved child grid is 200pt. An autofitting parent
  can instead grow to 241.5pt; the fixed-parent rule must not apply there.
  `_textBox` passes the fixed-parent context and current cell text width
  to the child's layout; percentage widths may shrink below the saved
  grid in this context, and the child does not independently autofit.
  This is layout context only; the nested table's saved properties stay
  unchanged. The cache includes the current available width and context.
  In `nested-minima`, all nine marker right edges agree with Word within
  0.06pt; six formerly wrong cases improve, three autofitting-parent
  controls stay unchanged. Tests exercise explicit widths, percentages
  above/below the saved grid width, and the autofitting-parent control.

  The original drawing banner is still unresolved: its parent autofits.
  Writer grows its nested grid from [0.3,171.3] to [0,177]pt, while Word
  retains the narrow first column and lets the 175.5pt picture plus its
  1.5pt effect overflow the second. Removing the neighboring logo lets
  Word redistribute the parent columns and fit that picture, while the
  smaller banner still ends at the parent's right edge. Parent and child
  sizing must be coordinated; suppressing every nested autofit would
  break the controls. Changing parent cell percentage preferences to
  auto does not explain the difference. Additional wide-image/long-word
  labs keep a 468pt table at the page width, including with `noWrap`, but
  older `caplong`/`at*` labs can exceed the page; a universal page-width
  cap is not justified. Measurements and reproducible package-building
  scripts are retained with the labs.
  Validation: all 454 Office tests and repository lint pass. Full
  577-document sweep converts every file successfully; per-file line
  scores, physical page counts, image counts and image bounds are
  unchanged from picture-effects/sweep. The three corpus documents with
  explicit fixed parents also retain identical text-word bounds. POI
  text-bearing mean remains 98.7%; nine textless files remain N/A.
  Artifacts: `nested-table/sweep/comparison.txt`, `image-comparison.json`,
  `fixed-parent-text-comparison.json` and `tests-final.log` under the lab
  directory above. This fixes the isolated fixed-parent cases, not the
  original autofitting-parent banner or a corpus line-score gap.

- **A hint sends block elements to the East Asian face too (2026-10-23;
  Windows 01QbbApP, from Word's print).** zh-340d52e9's "▓3.其他經區公所…"
  begins with a run whose Latin face is 新細明體, hinted East Asian, with
  no East Asian face of its own, so it takes Normal's 標楷體. Word's print
  sets its "▓" (U+2593) in YaHei Bold, and the line stands taller for
  it, both of its lines 25-29pt apart where the table's others are 18.
  Ours set it in the Latin face. `isEastAsian(_:hinted:)` let the hint
  take box drawing (to U+257F) and geometric shapes (from U+25A0), but
  skipped the block elements between them (U+2580-259F); it now covers
  the whole run. Only zh-340d52e9 and zh-045c5a75 in the corpus have
  such a character. zh-340d52e9 76.0 -> 97.7; zh-045c5a75 unchanged
  (pair bl-base/bl-new).

- **A group's freeform shapes are drawn (2026-10-23; Windows 01QbbApP,
  from Word's prints).** zh-ae2dd08d's and zh-ab9cbe66's flowcharts draw
  their boxes, diamonds and documents as `a:custGeom`: one-unit paths
  (`w`/`h` 1) over guides like `*/ f0 1 1`. Word prints every edge. Ours
  drew their text and arrows but no outline, because
  `WriterGroups.register` read a `wps:wsp` only with an `a:prstGeom`.
  It now reads a custGeom through `FreeformGeometry.parse`, the slides'
  guide evaluator. zh-6cd1befe p58's burst and boxes come back the same
  way. Only these three documents have such a shape. No line score
  moves (the scorer reads text); the pages compare against Word's
  prints by image (cg-base/cg-new). Left: text in a freeform is set
  from the box's top inset, not the geometry's own `a:rect` (zh-ab9cbe66
  p17's diamonds stand their text high).

- **The text boxes of a group's groups are read (2026-10-23; Windows
  01QbbApP, from Word's prints).** zh-ae2dd08d p21's flowchart (in a
  table cell, wrapTight) is one group holding twelve shapes, its eight
  text boxes two groups deep. Ours read only the first box's text, set
  across the whole group, because the group's text boxes were taken
  from its direct children alone (`group.all("wps:wsp")`).
  `_groupTextBoxes` now walks the groups in it too, each box at its
  place through every level's `chOff`/`chExt`, in document order, and
  both readers set each box's text where it stands. Seven documents
  have text boxes in nested groups: zh-61b62a40 95.2 -> 98.6,
  zh-bdae17c0 97.2 -> 98.1, zh-ab9cbe66 93.6 -> 94.6; the other four
  are unchanged (pair ng-base/ng-new). Left: text in a slanted or
  freeform box takes the preset's text rectangle only (zh-ae2dd08d p21's
  parallelograms set their text a little left of Word's).

- **In the autofit measure a closing mark stays with the Latin word
  before it (2026-10-23; Windows 01QbbApP, lab `af` on Word for
  Windows).** zh-ae2dd08d p24's table (tblW 10050, autofit) keeps its
  grid in ours, 90.5/70.9/71.4/269.7. Word prints it
  90.1/73.8/70.7/268.0. Its column 2 holds "【05-01】" under a 36pt
  hanging indent. The lab reproduces Word's re-fit with the table as
  saved. Without the brackets, or without the indent, Word keeps the
  grid. So Word's narrowest setting parts "【05-" / "01】", and "01】",
  at the indent, is the piece that is over (36 + 26 + margins).
  Ours had parted "01" / "】" since zh-82b166b4's "（WebHR）" (Word sets
  "（W" / "ebHR）" there), making every full-width mark beside a Latin
  word a piece. That holds for an opening mark, or one before the word,
  but not for a closing mark after it. 210 documents have a Latin
  character before a full-width closing mark in a cell: zh-ae2dd08d
  51.4 -> 54.8, nothing else moved (pair cl-base/cl-new).

- **A section-ending paragraph of floating objects stands on its page
  (2026-10-23; Windows 01QbbApP, lab `ax` on Word for Windows, from the
  Mac's report).** zh-6d402586's annexes are each a section of one
  paragraph that is itself the break: annex 1's paragraph holds the
  page's picture (VML, behind the text since 1571f2a4) and the
  page-relative "附件1" box; annex 2's its box and a wrapNone picture
  26pt over it. Word draws them on the annex's page. Such a paragraph
  takes no room (`_layoutParagraph`), and pagination's
  `while cursor < bottom` gave it no piece at all, so its objects were
  drawn nowhere and the pages stood blank. It now gets a piece of no
  height where it stands. Lab `ax` (body 70-76 alone): with "x" added
  to the paragraph, ours drew both annexes as Word does; without it,
  neither. Seven documents end a section in such a paragraph (pair
  ax-base/ax-new). By image: zh-6d402586 pp15-16 match Word's; the
  covers of zh-76700e5f, zh-9db183d5 and zh-cd8987db get their rule
  under "发布/实施" back; zh-e0ca7252 p41 its "注：本一覽表…" note.
  Lines: zh-6d402586 61.9 -> 62.2, the rest unchanged. Left: zh-6cd1befe
  p52's diagonal line is anchored in the empty paragraph after a
  page-anchored floating table (`tblpPr` vertAnchor page). Word draws it
  at the table's top-left; ours, now drawing it, puts it under the
  table, where our flow sets that paragraph.

- **A floating table nested in a cell floats there (2026-10-23, T133;
  Windows 01QbbApP, lab `tf` on Word for Windows).** zh-291fcea7 p5's
  flowchart is one cell holding wps shapes and four small tables with
  `w:tblpPr`: "page" at 29.25 and 320.85pt, "margin" centred, text-
  anchored 25.75, -57.2, -125.1 and 67.1pt from their paragraphs. Word
  sets them side by side, measured from the cell, not the page: their
  left rules at 29.5 and 321.2pt from the cell's left edge (60.98), the
  centred two centred on the cell. Ours read each as a block in the flow
  and stacked them down the page. A small nested table with `w:tblpPr`
  is now read as a floating box (`ImageFloat` from the cell, its
  `horizontalFrom` "cell" and the cell's own edges, its y from the
  paragraph, wrapped). Its paragraph takes no room, as Word gives the
  table none, and the box's copy of its style floats it no further
  inside the box. The four boxes' text stands within 0.3pt of Word's
  print (96.1/243.1/387.8/244.7 to ours 95.9/243.2/387.5/245.0).
  zh-291fcea7 40.2 -> 61.5 and 12 pages as Word's; zh-ad224275 98.1 ->
  100. They are the only two with such tables (pair tf-base/tf-new3).

- **A text-anchored floating table whose offset finds no room goes to
  the next page and keeps its offset there (2026-10-24; Windows
  01QbbApP, from the Mac's re-check).** zh-ad1e59ac's form is
  `w:tblpPr` vertAnchor="text", tblpY 205 twips, and it follows an empty
  "Normal (Web)" line that ends page 9 at 695.95 of 697.9. The 10.25pt
  offset puts the first row's top past the foot. Ours let `splitRow`
  part the row there: nothing stayed on page 9, and the rest opened
  page 10 at the margin, so every row stood 10pt high. Word's print has
  the table's top rule at 82.32-83.04, 10.25pt under page 10's margin.
  Now, where the offset would leave the row's top at or past the foot,
  the row goes to a new page first and takes the offset there. Ours is
  82.62 to Word's 82.68 centre. Over the 63 corpus documents with a
  text-anchored tblpY > 0 (pair ad-base/ad-new, same base):
  zh-ad1e59ac 93.6 -> 99.1, zh-4a90bb2fd 96.5 -> 98.8, zh-9ba2ead7
  90.9 -> 92.6, zh-cec9d337 90.3 -> 90.5, nothing lower.

- **Under `w:useAltKinsokuLineBreakRules`, before 2013's layout, a
  centred mark at a line's end does not hang (2026-10-24; Windows
  01QbbApP, lab `pc` on Word for Windows, routed by the Mac).**
  zh-12c4f07a p11 sets "…其他可能影響履行本契" and sends "約、" to the next
  line. That paragraph's line is 標楷體 13pt in 311.85pt, so "約、" is
  0.15pt over. The document has no compatibility mode, compresses
  punctuation, is zh-TW, and sets that switch. Ours hung the "、" by
  half an em (`hangsHalf`) and took it. Lab `pc` sweeps w:right on the
  line with its "、" at the end (E), inside the line (M) or absent (N).
  In the file's own settings Word takes E only to 0.15 over (no hang,
  no squeeze), M to 6.15 (the inner mark's half) and N not at all. The
  same holds justified (pcJ). Without the switch (pcA), E hangs whole,
  to 12.5. Under mode 15 (pc15) all three already matched ours. A
  centred mark has no blank half to hang by, so where marks hang only
  half (Word's "ink" half), it now hangs nothing anywhere in the
  paragraph, as it already did at the paragraph's end. Of the five
  corpus documents with these settings (pair pc-base/pc-new, same
  base): zh-12c4f07a 83.7 -> 84.3, zh-64044a1d 99.3 -> 99.4, the rest
  unmoved.


- **Before 2013's layout, an autofit cell's pieces are measured from
  where a hanging line starts, and a positive first-line indent asks
  nothing (2026-10-24; Windows 01QbbApP, lab `af` on Word for
  Windows).** zh-12c4f07a p19's floor column is 63pt on the grid. It
  holds "樓層" and "3樓/4樓" under 42.55pt indents that hang all the
  way. Word keeps the grid. Ours asked for the indent and an ideograph,
  66.4, and the column beside it lost a character a line from p19 to
  p28. Lab `af` puts one column-0 paragraph in each copy of a 3-column
  auto table with a 51.1pt first column, under modes 15, 14 and 12. In
  mode 15, "表現" under a 48pt indent hanging 24, "3樓/4樓" hanging all
  of 42.55, and "表" after a 75pt first line all widen the column, as
  ours already did. That is zh-1661a432's "表現" (100.0 in the base).
  In modes 12 and 14 each keeps the grid. A 100pt left indent, a 70pt
  right one, and a Latin word wider than the column from the hanging
  start widen it in every mode, by the same amount. The minimum is
  now, before mode 15, the left indent less any hanging indent, plus
  the widest piece, plus the right indent. A first try had capped
  one-line paragraphs in every mode, and it took zh-1661a432 to 95.7
  and zh-ae2dd08d down 0.8, both mode 15. On the 236 corpus documents
  with indented cells in autofit tables (pair afbase/af2, same base):
  zh-12c4f07a 84.3 -> 90.4, nothing else moved.

- **In Windows mode, a page printed with its markup stands as Word for
  Windows prints it (2026-10-24; Windows 01QbbApP, lab `bp` on Word for
  Windows, landed by the Mac).** Word for Windows fits the page and a
  3.7in markup area to the paper's width, with no 36.5pt spare, so
  scale = width / (text right + 266.4). The page sits at the paper's
  left edge, centred top to bottom. The pane runs from 9pt past the text
  to the paper's edge (257.4pt). Balloons run from 31.5 to 261.8pt past
  the text, with their line 1pt under the top and 1.8 over the foot.
  The connector turns 4.6pt past the text and meets the box 6pt under
  its top. Word's own balloon face is Segoe UI 9pt at 1.33 em lines, and
  it also stands in for a Balloon Text in Lucida Grande, which Windows
  lacks (58067). Lab `bp` (seven page geometries) and word-win's five
  pane prints agree within 0.3pt. A landscape page is not modelled:
  Word fits it as if on portrait Letter. Word for Mac's frame is
  unchanged. On the Windows series (pair w1/w2, same base d66805b8, both
  scored with the PyMuPDF matcher): POI 85.5 -> 89.0. testComment and
  58067 0 -> 100, Tika-792 0 -> 66.7, WordWithAttachments 10.5 -> 73.7,
  delins 11.9 -> 69.5, zh-3fe252ff 33.3 -> 99.4, nothing lower.
  comment.docx scores 0 by construction: its one comment has an empty
  scope in an empty body, so Word for Windows draws no balloon and
  prints no text (checked twice by windows).

- **In Windows mode, a comment of no text at the document's very start
  gets no balloon, and Word for Windows' balloons stand 1.1pt apart with
  their lines 2.2pt in (2026-10-24; Windows 01QbbApP, labs `na` and
  `bh` on Word for Windows, landed by the Mac).** Lab `na` (12 variants
  in comment.docx's own package) shows that only a lone reference or an
  empty range at offset 0 loses its balloon. Anywhere after text, a
  space or an empty first paragraph keeps it. With nothing else marked,
  Word prints no pane (comment.docx). Lab `bh` (four Balloon Text faces,
  three sizes, three line spacings) puts every stacked box 1.07-1.21pt
  clear of the one above, with its lines 2.15-2.3pt inside the top and
  the foot. Word indents a deletion balloon (8.8) only when it holds
  deleted list items. Mac mode is unchanged. On the POI set plus
  zh-3fe252ff, Windows mode, same base ab10de75, PyMuPDF matcher:
  Tika-792 66.7 -> 100, delins 69.5 -> 74.6, comment.docx's page count
  now Word's, nothing lower.


- **Mac body lines can compress an opening mark after Latin text with
  kinsoku off (2026-10-27).** zh-72da925e p8 ends `…最終目標-「` in
  a fresh Word print; the comma and quote share 7.43pt. A control with
  `5「` keeps the quote too. Permit the existing fitting calculation
  for a standalone opening mark after an ASCII non-space character,
  in Mac body text. Extending this to an opener after an ideograph
  was rejected: the same document lost 310 matched lines. The narrow
  version recovers the three p8 lines, 1135→1138/1309; paired full
  Windows/Mac sweeps have no other score or page-count changes.


- **A paired mark's restored blank limits Mac opening-mark compression
  (2026-10-28).** With kinsoku off, Mac body lines can compress punctuation
  to keep an opening mark after Han too: e0ca7252's first line ends `日（`.
  When the preceding mark closes up to it (`「（` or `）（`), splitting the
  pair restores the preceding mark's blank half. Deduct that half from the
  alternative line's stretch room when comparing stretching with compression.
  At 14pt with two commas, fresh Word controls take `甲（` 10pt over but not 12;
  paired marks take 4 but not 6, with and without a character grid. This explains
  the earlier broad candidate's 72da p56 regression: it counted the shared half
  as room to stretch. Windows and cell behavior remain unchanged.
  Full same-base pairs on engine 3841e45e: 756 documents/mode, zero drops,
  no page changes. Mac zh-72da925e 1138 → 1144/1309, zh-e0ca7252 1058 → 1061/1669; all other
  geometry unchanged. `test/office-opener-fit.py` embeds a small OFL Noto
  subset so its 12 Word boundary controls also run in the browser without
  installed CJK fonts; baseline fails and candidate, browser and Word pass.


- **A wrapping Mac body Latin word takes its preceding automatic gap
  with it (2026-10-28).** In the modern off-grid compression-versus-stretch
  comparison, that gap is neither occupied width nor a stretch opportunity
  on the alternative line. Internal automatic gaps still count. Fresh Word
  controls take e0ca7252's `第92` with 4.45pt left before the number, but wrap
  its date paragraph's `109`, whose preceding line has four internal gaps.
  Keep the existing half-prior-character path and Windows, cell, grid and
  marked-word rules. Full same-base pairs: 756 documents per mode, zero drops,
  no page changes; Windows geometry unchanged, Mac e0ca gains 118 matched
  lines. Unscored boundary improvements in bdae17c0 and dc9cfa34 also match
  Word. Five Word-printed embedded-font controls in `office-latin-fit.py`
  pass native/browser and reject the old binary. Fine size-dependent edges
  remain measured residuals; this is not a general tolerance relaxation.


- **Mac balanced spaces in an embedded subset with a Latin ASCII face
  (2026-10-27).** Where the embedded East Asian subset lacks U+0020 and
  the run has a Latin ASCII face, ordinary balanced spaces take 3/8 em.
  Fresh Word tc22 controls give 4.5/6/7.5pt at 12/16/20pt, and still
  6pt at bold 16pt; Times and Arial agree. Removing embedding or using
  ordinary FangSong, SimSun, KaiTi or YaHei restores half an em. Naming
  the subset for ASCII instead invokes a wider fallback, so that case
  keeps its old rule; mixed NBSP runs do too. Paired Windows/Mac sweeps:
  zh-c2229d4a Mac 113→265/265, all other scores unchanged. The earlier
  universal Mac exemption and subset-only candidate were rejected.


- **YaHei geometric shapes use their own advances (2026-10-27, T227).**
  Word's msyh.ttc and msyhbd.ttc agree: □ and ● 1336/2048 em,
  ◇ and ◆ 1229/2048, ※ 1724/2048, ←/→ 1 em, ↑/↓ half an em.
  Set those in both regular and bold tables. In particular □ no
  longer inherits ■'s narrower advance. Triangle/star fallback stays
  with SimSun. Paired full sweeps: Mac zh-e0ca7252 gains 2 matched lines,
  zh-20c1d74a gains 1 and zh-505b9619 gains 4; no drops in either mode.


- **A continued Windows table row uses its own top rule (2026-10-27).**
  After a page break, a stated row height includes that cell's own
  top border plus its stated margins, excluding the preceding row's
  bottom border. Store the original top rule before border sharing.
  The t135 pair recovers all 44 missing lines of zh-13552a3a (854/854)
  and four lines of zh-0978dee9, with no drops in either mode; Mac
  output is unchanged. Its page 27 final row ends at 504.55pt (Word 504.94),
  instead of 489.45pt. See the handoff continuation on the task board.

Mac Word gives explicitly named MS Gothic and Segoe UI their own line metrics,
including in a paragraph that mixes them with JhengHei. Fresh five-line 12pt
controls give MS Gothic 15.6pt steps (1.3 em, baseline 0.859375 + 0.15) and
Segoe UI about 15.96pt (2210 above + 514 below, per 2048). Do not map those
heights to YaHei or Arial merely because those faces draw the stand-in glyphs.
The zh-8d72961c mixed-line drift was those mappings, not a need to force one
height on every line: both-mode pair `parity-final` → `mixed-faces` fixes all
14 vertical misses with nothing else moving.

MS Gothic's own metrics apply only where its cmap contains the character.
In Mac Word, missing ideographs use Microsoft YaHei, contributing that face's
height. The all-Gothic variant of zh-8d72961c agrees for 167/167 Chinese
characters; embedded faces retain their existing coverage handling.

A tab separates words in `_wideWordStarts`. Treating it as part of a long
word after a full-width colon inserted a hard break before the tab, stranding
its held space on a blank line (zh-6a4fc013 Q5). Let the tab and the engine's
existing long-word handling place the text. Do not generalize this into
ignoring literal NBSP prefixes: the fresh Word NBSP + ZWSP control really
does leave a blank line. Full paired sweeps gain 51 Windows / 53 Mac lines,
with no other document changes; tab indentation remains a separate issue.


- **A moved flat-pie label starts from its frame-constrained default
  in Word (2026-10-28).** Apply the chart-frame constraint before the
  label's manual offset, then keep the existing final frame constraint.
  zh-61aaad09's outside default reaches above its frame; moving it first
  lost 9.7 pt of the requested downward move. Fresh original-package Word
  controls at 1%, 15.85% and 35% apply the same −33.177 pt / +14.16 pt move
  from the constrained outside position. Restrict this measured rule to flat
  Word pies; 3-D, doughnuts, bar-of-pie and other hosts retain their paths.
  The label now starts 604.879 pt down against Word's 604.804. Full paired
  sweeps: 756 documents per mode, zero drops or page changes; only 61aa
  changes, gaining two matched lines in each mode. Four self-contained Word
  controls verify full moves and untouched labels in native and browser,
  rejecting the old 5.817 pt partial move. General 3-D fitting/collision and
  remaining horizontal/legend differences are still unresolved.


- **Legacy Mac cell words distinguish separating spaces from spaces elsewhere
  (2026-10-28).** Ordinary spaces inside parentheses do not exempt an attached
  Latin word from the existing half-character fitting limit. Moving one space
  immediately before the word does, at the same natural width. A single Latin
  character keeps that limit too; measure the character itself, excluding an
  attached pause mark, while requiring capacity for the entire word. Fresh Word
  controls of zh-7b08d744's form wrap A and A、 at right 0/−2 twips and keep both
  at −5. Treating the entire A、 as the leading character incorrectly rejects
  zh-23ee8575's 2、 and zh-540dc149's 3、; those counterexamples are preserved.
  Windows, body and modern-layout paths retain their existing rules. No new
  tolerance or modern share test is applied to legacy cells. Full paired sweeps:
  756 documents per mode, no drops or page changes; only Mac zh-7b08d744 changes,
  149→210/210 matched lines. Eight portable Word controls with an embedded OFL
  CJK subset and explicit Arial spaces/letters pass in native and browser. The
  PDF test asserts the embedded font was loaded, so native fallbacks cannot hide
  an invalid fixture. The sub-twip −2 boundary remains a known private metric
  miss; it is not patched with an epsilon.


- **A missing Mac title face may name Arial Unicode MS as its alternate
  (2026-10-28).** Extend the existing known-missing 方正/small-title-name path
  to this alternate, as the GB2312 path already does. Each first document of a
  fresh Word process chooses ArialUnicodeMS for zh-d5cc99a6's original title,
  YaHei when only the alternate is removed, and SimHei when it is changed to
  黑体. Keep installed/embedded faces, other missing-name families, author-font
  mode and Windows rules unchanged. Full same-base pairs: 756 documents per
  mode, no score drops or page changes. Mac d5cc309→435, c25d673→738,
  08e952183→2251 and a78d423→424 matched lines; Windows geometry unchanged.
  Six portable controls pair explicit faces with missing names and their
  alternates; the native Mac-reference-mode test rejects the old binary.
  These Mac-only expectations are not a browser-font-mode assertion: WASI
  exposes no OFFICE_WORD_FONTS environment. The separate generic staged-web
  CJK fallback gap is recorded on the board, not hidden by test fonts.


- **A single grid line may clear a floating table before its grid cell ends
  (2026-10-28).** For a one-line paragraph above a page-wide floating band,
  exclude the lower half of its grid leading from the collision extent. Use
  the existing minimum allowance across all its faces: a smaller first run
  must not let a larger following run overlap the table. Keep explicit line
  heights, off-grid text and multiline paragraphs on their existing paths.
  Fresh whole-package Word controls of zh-291fcea7 place an empty anchor, X or
  文 above the table at87.95pt; X goes below at82/84pt and stays above at86pt.
  The attachment caption consequently fits on page11, and the final table
  returns to Word's position on page12. Full paired sweeps: 756 documents per
  mode, no drops or page changes; only Mac291f moves,232→281/296 matched lines.
  Twelve portable Arial controls pass natively in both modes and in browser:
  ten Word baselines plus two safeguards against later glyphs overlapping the
  table. First-run-only and unrestricted-multiline prototypes were rejected.
  General multiline flow around page-wide floats remains a separate gap; the
  safeguards permit its eventual correction without asserting the old positions.


- **Minimum line heights use the controlling text run's baseline (2026-10-28).**
  For a first line of non-East-Asian text, consider its non-space, non-picture,
  normal-script runs under an “at least” height as under automatic spacing.
  Choose the controlling baseline before adding the minimum-height leading:
  a small initial run can otherwise stand lower than the large run when the
  minimum exceeds both natural heights. Exact heights keep their existing
  placement. Twelve fresh Word Arial controls cover letters/spaces before a
  larger run, minima below/above the natural line, exact/automatic spacing,
  and a 30pt grid. All pass in native Windows/Mac modes and browser; the old
  binary fails, and exact/auto controls remain pixel-identical. Full pairs:
  756 documents per mode, no score or page-count changes. Seven normalized
  positions in Mac bug59058 and both-mode bug65649 move toward or onto Word,
  within the scorer's existing allowance. The standard-cover investigation
  exposed this rule through no-picture controls; its original inline-picture
  baseline and Mac print-paper crop remain separate, unresolved issues.


- **Small inline pictures keep a larger text line on the grid (2026-10-28).**
  A single ordinary non-East-Asian line with an inline picture must retain
  its text height and baseline when the picture fits above that baseline.
  Previously its height was replaced by the picture's grid pitches, which
  could shrink a62.4pt text line to31.2pt and shift its ink up a full pitch.
  Keep the larger of the natural text line and picture pitches; place the
  text at its controlling run's baseline. Larger pictures retain the existing
  picture rule. Exact heights, off-grid lines, combined text, raised/scripted
  runs and East Asian text stay on their measured paths. Two twelve-page Word
  fixtures cover24/48pt text, five picture heights, grid on/off and picture-
  only lines. Native both modes and browser pass; non-target control pages
  remain pixel-identical. Full756-document pairs have no drops or page changes;
  only zh-76700e5f's cover baseline changes, gaining one matched line per mode.
  Its paper-cropped Mac appendix reference and empty-list labels are separate.


- **Empty list numbers honor their visible mark and paragraph alignment (2026-10-28).**
  Preserve an explicit `w:vanish w:val="0"` in the character switches and
  DOCX output. For an empty paragraph, its visible mark overrides a hidden
  paragraph style, so both the number and the mark's line remain. Reserve
  the number and suffix width in the empty line just as for a list with text;
  centered/right numbers then travel with the line rather than staying at
  the left indent. Eighteen Word controls cover each alignment, normal/hidden
  styles, and off/omitted/on marks. Both native modes, saved copies and browser
  pass; all six explicit-off mark tags survive saving. Full756-document pairs
  restore seven reference lines per mode with no drops or page changes.
  Additional table/appendix number x positions move to Word's, leaving every
  other span position unchanged. This resolves empty marks only: general
  hidden body runs also need inherited hidden paragraph-mark joining and
  visible-mark line-height handling. A broader prototype failed those Word
  controls and was rejected; the accepted version keeps all eight nonempty-
  body control pages pixel- and geometry-identical to the prior renderer.

- **Missing English GB2312 names in Mac reference mode (2026-10-28).**
  An undeclared, unembedded FangSong_GB2312 or KaiTi_GB2312 is an absent
  Latin font name in fresh Word for Mac: Cambria letters and quotes with
  SimSun ideographs. Keep font-table and installed-face rules separate.
  Five Word controls reproduce the distinction;38 non-target pages retain
  baseline pixels. Full same-base756-document pairs have no drops or page
  changes, Windows geometry unchanged, and zh-202582e2 rises116→129/138 in
  Mac mode. Twelve newly matched lines have Word's entire normalized text;
  one still differs at its end. Browser parity and all layout gates pass.
  The remaining mixed-size baseline and explicit kinsoku0 rules are separate
  measured gaps, not covered by this font correction.

- **Explicit punctuation restrictions without FE layout (2026-10-28).**
  Honor paragraph `kinsoku=0` even when `useFELayout` is absent: closing
  punctuation may start a line, and an opening mark may end one under the
  existing East Asian language rule. Added invisible breaks contribute no
  line height; a mixed-size Word pair catches the rejected marker that
  shifted following text. Preserve the existing FE-layout path. Full756-
  document pairs have no drops or page changes, Windows geometry unchanged;
  zh-202582e2 rises129→136/138 in Mac mode, all seven new full lines matching
  Word. Native and embedded-font browser controls pass. Unembedded Chinese
  font coverage in the local browser build, mixed-size absolute baselines,
  and the old FE-path marker-height behavior remain separate measured gaps.

- **Mac SimHei line height and legacy row-border clearance (2026-10-28).**
  Fresh Word prints at10,10.5,12,14 and18pt bound SimHei's automatic advance
  to1.29684110–1.29697071em; use332/256em, preserving its Latin advances and
  Windows metrics. Separate paragraphs, styled breaks and both font aliases
  agree. Word for Mac also requires the full closing border when a mode12
  table row meets a page foot; the legacy half-border allowance belongs to
  Windows mode. Ordinary/merged rows, minimum/exact/automatic heights and
  asymmetric top borders confirm this independently. The border correction
  prevents the shorter font's header from wrongly admitting an extra row
  in zh-90e0cea8. Full756-document pairs have no drops or page changes:
  zh-4c5da793 rises580→680/680, b00 gains one line,90e0 retains323/326;
  Windows geometry is unchanged. Native controls and full browser gates pass.
  Unformatted-break defaults, SimSun precision and unembedded CJK browser
  fonts remain separate measured gaps.

- **Mac table closing line and a paragraph-final Latin ")" (2026-10-28).**
  Word for Mac, like Word for Windows (eba13300), hangs a table's own single
  bottom line (`w:tblBorders`) under an exact last row: zh-884c6e3e's fresh
  Mac print sets the text after each such table ~0.45pt lower and leaves p2's
  fourth line for p3. Lab `rb`, which kept the line inside, ruled its cells.
  And from 2013's layout a paragraph's last character that is a Latin ")" or
  "," hangs whole before the line's marks are weighed: `squeezedFirst` no
  longer holds it to the whole over (zh-e0ca7252 "…免載於招標文件)", 14.25
  over, marks 20.6: Word takes it). Pair b0→c1, 756 documents per mode:
  Mac 884c 49.5→100, e0ca 70.5→99.1; Windows identical. zh-b0401810 loses
  one Mac line by cancelling errors (its last row's text had stood 0.5 high,
  hiding a 0.46pt id/number column baseline difference every row has).
- **A line exactly as wide as its room: Word's double sum decides (2026-10-29).**
  Word sums a line's room in doubles, each measure in twips made points on
  its own (÷ 20) — column, less the left indent, plus the hanging one, less
  the right — and a line needing all of it fits only if that sum reaches its
  width. 5.4 is not a double, so some indent pairs land a hair short: lab f39
  (Word for Windows, zh-f39e54b6's package, 62 prints a twip apart in left,
  hanging and right) parts on exactly that, 441.0 against
  440.99999999999994; no rounding of the measures to a unit fits. Ours took
  every such tie (0.001 slack, the fitter's `hair`/`edge`); now a line whose
  sum falls short refuses it. Pair on the Windows box, 756 documents per
  mode: zh-f39e54b6 94.5→95.9 Windows (第十四條 sends "日" down, 第十五條
  keeps "查", as both Words' prints), every other document identical.
- **Three Windows-host causes: Thai breaks, a missing cs face, WordArt's extent
  (2026-10-29).** (1) Word for Windows breaks Thai only at spaces, but the
  switch (`thaiBreaksAtSpaces`) was set only once Word for Mac's cordia.ttc
  had loaded, which happens on macOS alone; a Windows host broke Thai at ICU's
  dictionary boundaries. It is now set on Windows hosts too, and the Windows
  Thai face takes Browallia New's advances (2.5% narrow over 11,356 letters)
  in place of a class scale. zh-6a4fc013 48.5→66.9 Windows-hosted, the bulk of
  the ~0.09 zh gap between Windows- and Mac-hosted Windows mode; residual: p18
  keeps a bold heading on one line where ours breaks after "：". (2) A cs face
  neither embedded nor installed ("Noto Sans Arabic UI" in POI `rtl`) fell to
  the platform default; on Windows that is Segoe UI, 1.33em, 15.96pt lines
  against Word's ~14. It now falls to Times New Roman: rtl 28.6→85.7 both
  modes. (3) An inline VML WordArt shape (text path, spt 136–175) adds to its
  line in Word for Windows' print 0.68 plus the larger of its outline's term
  (lab wa4: 0.84/2.28/11.28/19.56/30.0 at 0.5/1/2/3/4pt, in proportion
  between, past 4pt on the 3→4 step) and 2.28 for a shadow; within 0.02 of the
  lab but for the text's own part ("ОООО"/"IIII" at 1pt: 42.95 against 41.52).
  WordWithAttachments 73.7→81.6; its rest is p2's embedded document. Pair on
  the Windows box, 756 documents, Windows mode: only those three move; Mac mode
  (Thai+WordArt) only zh-6a4fc013 48.7→49.8.
- **A missing complex-script face: spaces in Cambria, Arabic in Times
  (2026-10-30).** Word-win's rtl print sets the Arabic of a cs face it has
  none of ("Noto Sans Arabic UI") in TimesNewRomanPSMT and its spaces and
  neutral marks in Cambria — 115 spaces of 2.64pt at 12pt, where Times' are
  3.0. Times as the primary face (2026-10-29) had fixed the lines' height but
  set the spaces in Times: each line took three letters fewer, 8 lines to
  Word's 7, rtl 85.7 — and on a Mac host, which had fallen through to the
  same split before, down from 100. The Cambria clone is now the primary
  face and Times' joining widths still set each Arabic word. Pair on the
  Windows box, office 8ac9be91, Windows mode, 756 documents: rtl 85.7→100,
  nothing else moves (v1 and v2).
