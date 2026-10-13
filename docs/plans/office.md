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

Measured and not built: **`w:mirrorIndents`** (3 of the 679, two in
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
body, page number formats and restarts per section, `w:topLinePunct`,
drawn lines and shapes (a red rule under a letterhead), and whatever
the next first-differing line turns out to be.
