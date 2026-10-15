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
