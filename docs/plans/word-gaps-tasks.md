# Word gaps — shared task board

Two sessions work on how Writer draws Word documents against Word's own
prints, on the `office` branch. This file is how they split the work:
**claim a task before starting it, by editing its `Owner` line and pushing
that edit alone first**, so the other session sees it on its next fetch.
Release a claim the same way if you drop it. The rules each fix found go
in `office.md` ("The painter against Word"); this file only says who does
what next and how to check it.

## How a fix is checked

The steering number is `test/docx-line-match.py WORK`: the share of
Word's lines our PDF sets on the same page at the same height (±3pt).
x positions are not compared, so a horizontal fix can be right and move
no score. The loop that has worked:

1. `python3 test/docx-line-match.py WORK KEY 8` (or
   `~/starling-word-check/lab/tools/missed.py WORK KEY` on the Mac) names
   the first line that parts from Word.
2. Read that paragraph's XML and its style; read glyph positions off both
   PDFs (PyMuPDF `get_text("rawdict")`, `get_image_info()` for pictures,
   `get_drawings()` for table rules).
3. When the rule is not obvious, build a lab document from the
   document's own package (`lab/tools/mklab2.py SRC OUT BODY`) and print
   it with Word (`osascript test/docx-word-pdf.applescript IN OUT`; Mac
   only). Labs are named in `office.md`.
4. Sweep the whole corpus, compare per document with the previous
   sweep, and keep only changes where nothing goes down (or say why).
   Convert with `OFFICE_WORD_FONTS=mac`. On macOS there is no `timeout`
   command: a sweep loop using it converts nothing.
5. `test/run.sh --office`: one known failure,
   `LineHeightTests.testSingleSpacingIsTheFacesNaturalHeight`.
6. One fix per commit; fetch and rebase on `office` before every push.

On the Windows box the line match reads the PDFs with PyMuPDF (c4a931e5),
and its numbers sit within a point or two of the Mac's once Chinese text
falls back to YaHei (9ecd33ea) — before that every line drawn there was
JhengHei UI and Yu Gothic UI, and the sample scored 59%. Build and run
as in its memory notes: `STARLING_ENGINE_OUT` to link, the engine's
out-dir on `PATH` and `STARLING_ICU` to run.

Standing, at 92c1b88a (2026-10-14): Chinese sample 79.6% of Word's lines
(median 92.9%, 57 of 68 with Word's page count); POI set 66.6%.

## Done on 2026-10-14 (session 011uWpmCQYr9neyJ1V1gzrrb)

Each has its entry in `office.md`.

- Table placement by alignment and compatibility mode; bold-face space
  width; a Latin word at a cell line's end (9f61ce99)
- Floating pictures that text wraps round, rotation (e9ad2983)
- Fixed-layout tables keep their grid; grid lines may hang past the
  page foot (8d854de9)
- Cell-ruled tables: unstated sides unruled (35cdc651)
- Picture lines in cells keep to the grid (dee02ae9)
- `leftChars` counts from the hanging line (e4a5cf77)
- Lone page-break mark holds its page before mode 15 (444b6614)
- Page numbers per section (aaeca4fd)
- `w:topLinePunct` at a paragraph's start (b4f5393e)
- Embedded faces are not swapped for YaHei (d5c74cec)
- Declared-Latin unknown faces set in Calibri (55b60b0e)
- Space after stays at the page foot (a0237668)
- Outside/inside alignment by page side (607bfce9)
- Justified mode-15 spaces give a quarter each (fe308378)
- Font-table `w:altName` for faces Word lacks (551ad92d)
- Gridded multi-line paragraphs use the tallest strut (02e1c405)
- Fit-to-text text boxes shrink to their text (92c1b88a)
- Lists over one definition share their numbers (c2ec89d9)
- A centred cell is set in its parted row's part on the page (c2542ff6)
- Kept runs: moved from their start, carried through kept table rows,
  over from a page's middle whatever their length (f67d5ba6, f774a736)
- Text-anchored floating tables stand their `tblpY` lower (dd1ad844)

## Done on 2026-10-15 (session 01Xgpbk5jLzrCcB28yZBzYHN, Mac, starling-ios worktree)

Each has its entry in `office.md`; every one swept against a clean
baseline at the same tip, nothing down.

- Embedded East Asian faces drawn (T8, 12684c7f); exported PDFs' text
  reads ideographs, not radicals (starling-engine a0cbed78)
- A no-break space is an em in a square face (c7c1610a)
- Theme fonts by script, and in headers/footers/footnotes (7a5bf43c):
  zh-1a3c7aa0 78.0 -> 91.7
- A header's/footer's fit-to-text box keeps its first page's width
  (36ecdfb8): zh-a4b0f6ea +6, zh-5901e2b0 -> 100
- "At least" rows add their cells' margins; hidden-mark empty cells ask
  nothing (afe8a68e)
- A document background brings a phantom header and footer (b18da088):
  bib-chernigovka 0 -> 90.3
- A line of spaces and tabs is its mark's line (f4cc1940):
  IllustrativeCases 76 -> 100
- A shape's text in its preset's text rectangle (78eabee3):
  shapes-with-text 37.5 -> 62.5

Leads measured and left (office.md): T1 autofit (released); text in
group shapes (5 files); a page-anchored floating table Word breaks
after its first row (zh-a4b0f6ea p20); frames with wrap="around" let the
next paragraph flow beside them (lab fr1; only 2 files have body frames);
drawing's nested HTML tables (flattened, T9's limit).

## Open tasks

Two sessions now share the Mac and its one Word. Word prints (labs,
`docx-word-render.sh`) must not overlap: before printing, check
`pgrep -fl "[o]sascript"` and that no other print is mid-dialog.
Sweeps are per checkout (`lab/tools/sweep.sh` run from inside the
worktree writes `~/starling-doc-check-<worktree>`), so they never clash.

Ranked roughly by lines at stake. "Known" is what has been measured;
start from there.

### T1. Autofit tables — DONE (2026-10-15)
Owner: session 017F2GnTfScURKYZPmRxVQvW (Linux dev box, no Word)
Built as office.md's "Autofit tables" has it (b7b42101): a cell whose
narrowest setting (its longest unpartable piece — spaces after a no-break
space joined — plus margins and side indents, negative ones too) is a
point or more over its grid columns is exactly that wide; the others give
way toward their own narrowest; the table grows only when they need it.
zh-0aac9d1a 63.3% -> 100% on Linux, nothing else moved. Why only its
first form re-fits: its stamp line is in 仿宋 (no-break space an em, a
444pt piece); the other three are 仿宋_GB2312, YaHei on a Mac, whose
no-break space is narrow. Still open, needs Word: how a span is shared
among its columns (ours 34.5/183.0/109.5/163.5 against Word's
34.6/187.6/110.5/156.4 — no line moves here). Lab: a span over three
columns of unequal grid and content, its narrowest varied.

### T2. Per-section column layouts — narrow case DONE (2026-10-15)
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box)
A section of columns filled by column breaks and followed by a
continuous section is read as a borderless table row (office.md):
zh-a0e932c2 22.6 -> 100%, zh-6cd1befe 85.2 -> 93.3. Still open: a
section of columns that runs over whole pages (zh-6cd1befe's seventh
section, two columns) is set in one column.
Documents: zh-a0e932c2 (23%, 7 pages to Word's 5).
Known: a section of three unequal columns filled by column breaks,
then a one-column continuous section on the same page. The layout has
one column count for the whole document (`pageSetup.columns`, slots of
`page * columns`). A larger change to pagination.

### T3. `w:mirrorIndents` — DONE (2026-10-14)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb
Built as measured (entry in `office.md`), with a relayout pass after
paging. Moves little: zh-06c46ba9's paragraphs hang by their left
indent. Its real gap is T10.

### T4. Heading spacing at a page's top — DONE (2026-10-14)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb
Space kept at a page's top is less the previous paragraph's space after
(entry in `office.md`). zh-64044a1d 27 -> 33, zh-6d1afa56 16 -> 36.
zh-64044a1d still runs 119 pages to Word's 103: the next difference is
open for anyone.

### T5. zh-6d1afa56: headings led by breaks
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box, Word for Windows only), from 2026-10-14
Documents: zh-6d1afa56 (16%), zh-1a3c7aa0 (24%).
Known: break-led headings came out at three different heights — likely
the T4 rule (re-check after it); in
zh-1a3c7aa0 the second (landscape) section starts pages earlier than in
Word, and the odd-page footer stands 8pt lower than Word's.
Note for the Mac session (parted rows are yours): zh-1a3c7aa0 page 14's
last row parts over the page with its centred name cell's first line
on 14; Word's part is 40pt (156.8 to 116.9) with that line centred in
it, ours runs to the page's foot with the line at the part's top, 4pt
high. c2542ff6 covers a cell whose text all fits; this one's does not.
Progress (Windows box): zh-6d1afa56 16% -> 97.9% (line-opening marks,
merged cells over a page foot, the blank page after an over-full page,
with T4's rule); zh-1a3c7aa0 10% -> 29% (YaHei fallback, its footer's
height, the odd/even blank page, the section mark's own page). Still
open in zh-1a3c7aa0: from page 13 the annex tables run long (93 pages
to Word's 90); even pages' "- 10 -" prints as "-10" in Word (its box).

### T6. Body pictures on the line grid — DONE (2026-10-14)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb
Snapped in the body as in cells (lab `pg`, entry in `office.md`).
zh-90e0cea8 now runs a page long from drift earlier on its last page
(ours 17.6pt below Word's there): open for anyone.

### T7. zh-abe7e063, zh-25c4de17, zh-799c91cd, zh-190d730c
Owner: session 011uWpmCQYr9neyJ1V1gzrrb (Mac, has Word), from 2026-10-14
- zh-abe7e063: done (symbols an em in square faces), 32.8 -> 91.7.
- zh-799c91cd: page 1 drifts about 2.5pt low by its foot, so its last
  line goes over. Word's 12pt lines step 20.64/20.4 (a 0.24pt raster,
  mean 20.58 = YaHei's 1.3198 em x 1.3); ours a steady 20.65. Tried
  and reverted: the tallest-run strut for every multi-line paragraph
  (no change here, two documents lost 24-32 points) and YaHei's height
  1.72 -> 1.7157 (no change here, slightly negative overall). Not the
  list label, the Latin run nor the 「」 quotes (tested by removing
  each). Open.
- zh-190d730c: its first difference is a scorer artefact (a justified
  line drawn out of order splits PDFKit's line). Not looked at further.
- zh-25c4de17: done (the column gap stated on w:col), 36.5 -> 100.
zh-799c91cd's page-1 drift found (Mac, 2026-10-14): the second line of
"（二）共同申請人同意由" stands 21.55pt under the first where Word's is
20.64 — its first line holds two runs of eight spaces in Times New
Roman (no hint); a copy without them sets 20.65. Word sizes the line by
its text. Two fixes tried and reverted: spaces set in the East Asian
face at Times' width (zh-33aa9899 98.6 -> 39.2, zh-e37f8d40 -15), and
spaces at a line height of 1.0 (zh-c3dd22c4 100 -> 14, zh-4b8e0abc
-31). Other documents' lines depend on what such runs do now; the rule
has to say which spaces Word leaves out of the line's height (at the
line's end? between East Asian text?), from a lab.
Solved (81b392cd, 96f82ce8): it was the zero-width space put in after
the held spaces, in the East Asian style, whose glyph came from the
Latin base family; and then YaHei's 1.715-em pitch. zh-799c91cd 82.3%
-> 91.2%.

### T8. Load embedded fonts — DONE (2026-10-15)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, starling-ios worktree)
East Asian embedded faces are loaded and drawn (office.md);
zh-e37f8d40 94.0 -> 96.6, nothing else moved. Latin embedded faces are
left to the clones on purpose. Found on the way and fixed in the engine
(a0cbed78): exported PDFs' text read radicals (⼈⺠) for ideographs in
every Chinese document. zh-e37f8d40's remaining misses: a line Word
does not squeeze to take "民" (p3, compressPunctuation, mode 14) and
table header cells.
Documents: zh-e37f8d40 (already 92.8% with the square model),
saut_page.
Known: `word/fonts/*.odttf`, obfuscated with the `w:fontKey` GUID
(XOR of the first 32 bytes). Not loaded; the name only keeps the square
face model.

### T9. Nested tables with hidden text — DONE (2026-10-15)
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box)
Documents: zh-454e2e29 (49%), row 2. Now 96.1%: a cell centres its text
with the text boxes anchored in it (ada8880e), two lines in one
(`w:combine`, 37a4a534), and a small nested table set as a table, a
block in its cell (223b723e). Still flattened: nested tables over 15
rows or 600 characters (a block cannot part across pages; 60329's
protocol is one), and any that nest further (drawing).

### T10. A section of one empty paragraph: a page or none? — DONE (2026-10-14)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb
Always a page, unless a page break just before is the same break
(entry in `office.md`, lab `es`). zh-06c46ba9 0.7 -> 47.2.

### T11. zh-90e0cea8: drift on its last page — DONE (2026-10-14)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb (Mac, has Word), from 2026-10-14
Documents: zh-90e0cea8 (67%, 11 pages to Word's 10).
Known: Word's last picture ends exactly at the page's usable foot, its
line's descent past it; ours now allows that (entry in `office.md`),
which took zh-6d1afa56 from 41% to 97% — note for T5's owner. This
document still needs about 1.3pt more: ours starts the picture's line
about 2pt below Word's, from drift earlier on that page. Open.
Progress (Mac): numFmt "none" levels (297b0f60) took it 67.5% -> 88.5%.
Left: page 10's text runs 0.54pt below Word's from the top, and the
last picture then misses the foot. The cause is the header: style 63,
ascii 黑体 / hAnsi 宋体, and its "—" is SimSun in Word's print but
Liberation Sans in ours (a taller ascent: the header's baseline 1.09pt
lower). Routing hAnsi characters to an East Asian hAnsi face works (it
resolves 宋体) but our 宋体 stand-in has no U+2014 and falls back to
Liberation Sans all the same — tried and reverted, no score moved.
Now 88.5% -> 67.8% after the list-number rule of 2026-10-14 (its 6.1.1
paragraph wraps as Word's, and 6.1.3 then misses page 5's foot by that
half point): fixing the header's "—" would recover both. The East
Asian style's family is the Latin stand-in (Liberation Sans) with CJK
glyphs from the system fallback; a glyph the stand-in has (U+2014)
comes from it with its metrics. The fix is in the face resolver: an
East Asian style whose family is a real CJK face, so its symbols and
their metrics are that face's.
Tried (Mac, 2026-10-14): the East Asian style's family set to PingFang
SC outright. The header's "—" then comes from the CJK face, zh-799c91cd
91.2 -> 96.0 and zh-9c5d0c3f 55.9 -> 66.7 — but every ASCII character
in an East Asian-hinted run comes from PingFang too, at its own widths:
zh-457a8d62 94.7 -> 19.9 (its "(許志堅子)" parens), zh-06c46ba9 -7.3,
zh-7dc3afad -4.0. Reverted; the narrow version (only the dashes and
ellipsis routed to the CJK face) is in — zh-9c5d0c3f 55.9 -> 66.7 — and
zh-90e0cea8's header line still stands 1.09pt under Word's with its "—"
from the CJK face. So the drift is not the dash: the 黑体 run's mono
stand-in (Liberation Mono at 5/6, baseline 1.005) is the next suspect.
Found: the header sub-layout took the body's line grid and centred its
10.5pt line in the 15.6pt pitch (11.44 under the top; Word 10.35).
Headers and footers now keep to no grid: 67.8% -> 83.9%, Word's 10
pages (commit after 49beaff9). Then its empty 0.7pt counter paragraphs
(zero in ours, 0.7 each in Word) — 83.9% -> 92.3%. What is left: the
cover page (frames) and page 2's table of contents, whose lines match
Word's glyph for glyph but whose leader dots the matcher's text
extraction groups otherwise.

### T12. Squeezing marks to fit a character: the limit on a character grid — DONE (2026-10-15)
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box). zh-d68ac84a 80 -> 99.2%:
the hang half (299b2ecd) and the squeeze's tolerance, which now stands
only off a character grid (on one ours are Word's widths exactly).
Documents: zh-d68ac84a (80%, first parting page 10).
Windows box, 2026-10-15 (299b2ecd): the hang half of this. Word hangs a
final mark to its em exactly (no hair), and keeps a character-counted
indent in whole twips (200 hundredths at 14.6465 = 586 twips): lab `hc`
on this document's grid; zh-d68ac84a 81.4 -> 83.8 (page 22). Rounding
each grid character to twips was tried and is wrong (75.6). The squeeze
case below is untouched.
Found (labs `pqgrid1`–`6`, `pqkin1`–`3`, `pqvar1`, `pqthr1` in
`~/starling-word-check/lab`, 2026-10-14): Word squeezes 。、，（） alike
on a grid of `linesAndChars` with negative `w:charSpace`, and its
first-line indent does not stop it. On the real paragraph Word takes
"学" with the line made 0.1pt wider and leaves it at the stated width;
our fitter puts that line 7.318pt over against a limit of 7.323 plus a
0.045 tolerance, and takes it. The difference is under a hundredth of a
point, below what our widths match Word's to: probably Word measures in
twentieths (the indent as 586 twips, not 2 × 14.646). Not worth chasing
without a model of Word's rounding.

### T13. zh-89385c94: cell lines and a page's foot — DONE (2026-10-14)
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box), from 2026-10-14
Result: 99.3% on Windows (2ffeece2, 3605f11c, with 37fdff4b).
Documents: zh-89385c94 (16% on Windows).
Known: page 2's cells take "考，" on a line Word ends a character
earlier, and the page's foot holds one line more than Word's.
Note from the Mac session (37fdff4b, pushed before this claim was
seen — sorry for the overlap): the extra line at page 2's foot came
from the carried-over row part at the page's top, which stood 0.4pt
above Word's for want of its top rule; with that, zh-89385c94 went
16.3% -> 51.0% on the Mac. The "考，" line break is untouched and
yours, as is the rest of the document. The Mac session will stay off
zh-89385c94 from here.

### T14. zh-06c46ba9: body lines two characters short from page 5
Owner: session 011uWpmCQYr9neyJ1V1gzrrb (Mac, has Word), from 2026-10-14
Documents: zh-06c46ba9 (47%, Word's 72 pages).
Known: page 5's body lines end two characters before Word's.
Progress (Mac): mirrorIndents parity by `doNotFlipMirrorIndents`
(5a7f5332), compound cell rules (91ca3fcf), footnotes laid out
(c7ffdfc9), an autofit grid wider than its share kept (fc60d952):
47% -> 75.9% (with 4b562bc1, list numbers' Latin digits). Page 5's
figure is SmartArt (word/diagrams), drawn as an empty box; the only
such document in the corpus. Pages 25 on: the footnotes and their room
match Word's to 0.1pt (separator 14.65, note lines 17.2), but table 9
on page 24 runs ~0.1pt a row taller than Word's — 1.35pt by its foot —
so the page's last line (exact 25pt) misses by 0.36 and goes over. Word
puts every line on a 1/300in raster (0.24pt); that is the open
question, not the notes.

Note for the Windows session: on the Mac, 2ffeece2 moved zh-9e08ed28
from 56.7% to 47.4% (Word's 22 pages: 21 -> 23); the sweep that showed
it held nothing else that touches that document.

Note for the Windows session (Mac sweep, clean baseline either side):
62ba13ec + 9491b2ba together moved zh-64044a1d 72.8% -> 67.1% while
taking zh-9e08ed28 47.4 -> 81.0, zh-e6d54ae4 64.2 -> 82.4 and
zh-89385c94 53.1 -> 98.9.

### T15. Charts in Writer
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box), from 2026-10-14
Documents: 61745 (two charts, nothing else), chartex, zh-37b6536f (p3).
Known: a chart (`c:chart` in a drawing) is kept as an empty box of its
size. Slides reads and paints charts (`ChartXML.read`, `ChartPainter`);
the plan is to paint them in Writer through a hook in RichLayout.
Progress: drawn (61745 0 -> 15/17 lines, zh-37b6536f 31% -> 96%), the
automatic title of an unnamed lone series, `cx:` charts by their
Fallback pictures, charts in a line of text (chartex: 3 pages as Word's).
Left: radar charts (Slides reads none; chartex's stays a grey box).
2026-10-16: stock charts read as their lines (735f39f0); a 2013-style
bar chart's plot top, ticks taking no room in a 2013-style chart, a
line's 19.2pt legend key (f9c1e61e..599f460a): 61745 100%, chartex 50.
Then a top legend's place, a radar's circle and labels (e80a1e35,
1148fce3) and box-and-whisker charts drawn from their chartex part:
chartex 76.4%, pages 1 and 2 all but one line. Left on chartex: its
sunburst (p3, 16 of 27 lines) is still its Fallback picture.

### T17. zh-9c5d0c3f: road-sign table rows — DONE (2026-10-16)
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box), from 2026-10-14
Documents: zh-9c5d0c3f (54%).
Note from the Mac (2026-10-14): 49beaff9 (dashes and ellipses in East
Asian runs set in the CJK face) moved zh-9c5d0c3f 55.9% -> 66.7% on the
Mac — found through T11, not taken from this task; what is left of it
is yours.
Windows box, 2026-10-15: its signs now stand centred in their cells
(c69db236) and the tables where Word sets them (2ff0daed: before 2013's
layout a spaced table is set out by its first cell's text inset). The
signs' rows a pitch tall: settled by 59fc1ee5 (a picture's line is as many grid pitches as the
picture is tall, its descent not counted): 81.6% -> 90.8. Left: page
6's continued row stands 5pt high (parted rows); p3's "停車再開"
(a 75pt sign and its caption in one paragraph, the caption wrapped
under it, "at least" 19.2) 9pt high; p4's "車道縮減" (snapToGrid off,
"at least" 11) 21pt high.

### T18. bug59058: a bordered run's picture line — DONE (2026-10-15)
Owner: session starling-office1-df (Linux dev box, no Word; starling-office1 worktree), from 2026-10-15
Documents: bug59058 (73.9% on Linux, 53 pages to Word's 52).
Known: from p27 its "tab1"/"tab2" pictures are inline in runs with a
character border (`w:bdr` single, sz 6, space 0, CCCCCC, frame). Word's
picture lines are 75 and 31.56pt for pictures of 72.75 (+0.75 effect
extent) and 30 — the border's 0.75 above and below; ours 72.75 and 30,
with no border drawn. Text runs with borders (zh-06c46ba9, 42) are left
alone until measured.
Built (office.md): the line holds the border and the effect extent,
the border is drawn. p27 within 0.3pt; bug59058 73.9 -> 74.9% (Linux),
nothing else moved. Its next parting is p38: the references drift about
0.1pt a paragraph lower than Word's (2.3pt by the page's foot).

### T19. bug59058 p38: lines mixing Times and Cambria — DONE (2026-10-15)
Owner: session starling-office1-df (Linux dev box), from 2026-10-15
Documents: bug59058 (74.9% on Linux).
Known: its references are 13pt Times, "at least" 15pt, with MinionPro
journal titles (Cambria in Word, Caladea here). Word steps a line with
Cambria on it 15.24 (on its 0.24 raster: 15.12/15.36), a Times-only
line 15.0; ours 15.45 and 15.0 — the engine's even leading puts half
of Times's padding under the baseline, so the mixed line is Cambria's
ascent plus that deeper descent. 2.3pt by p38's foot.
Built (office.md, "Times and Arial keep their line gap over the
text"): Writer draws Liberation Sans/Serif with the gap moved over the
ascent. bug59058 74.9 -> 89.1%, Word's 52 pages; nothing else moved
(form_footnotes -1.2 is the matcher joining a footnote mark to its
line). The browser build's copies (web-app.sh) were not built here.

### T20. Vertical text in cells (zh-2b955411) — DONE (2026-10-15)
Owner: session 017F2GnTfScURKYZPmRxVQvW (Linux dev box), from 2026-10-15
Documents: zh-2b955411 (89.7% on Linux; pages 26-28 lose 45 lines).
Known: `w:textDirection` tbRlV and tbLrV cells ("评估目的", "经济行为类型"):
Word stacks the ideographs upright, one a character's advance below the
other (9pt at 9pt). The reader turns tbRlV sideways (`.down`) and reads
tbLrV as horizontal, so that row is three lines tall, 6.7pt over Word's,
and the 282pt stamp row after it goes to the next page.
Done: tbRl/tbRlV/tbLrV read as turned with upright ideographs, drawn a
character at a time, distribute spread along the cell (office.md,
"Vertical writing in a cell"). zh-2b955411 89.7 -> 98.0%, nothing else
moved. Left: a turned paragraph with Latin in it is drawn turned whole.
`w:jc` distribute for horizontal text: built the same day (office.md,
"Distributed paragraphs"), no line moved, characters within 0.4pt.

### T20. bug59058 p45: an empty `<w:pict/>` — DONE (2026-10-15)
Owner: session starling-office1-df (Linux dev box), from 2026-10-15
Documents: bug59058 (89.1% on Linux).
Known: the paragraph before p45's table holds a run of nothing but an
empty `<w:pict/>`; Word draws nothing and gives it no room, ours a
300 x 200 grey stand-in, and the table stands 187pt low.
Skipped now: bug59058 89.1 -> 91.7%, nothing else moved. Next parting p48
("New Cases, Deaths and 5-Year Relative Survival", 4pt low).

### T21. bug59058 p48: Lucida Sans Unicode's line — DONE (2026-10-15)
Owner: session starling-office1-df (Linux dev box), from 2026-10-15
Documents: bug59058 (91.7% on Linux), the only one with the face.
Known: Word's print embeds Lucida Sans Unicode: hhea 2246/-901, no gap
(1.537 em, baseline 1.097 down); its 9.5pt single lines step 14.52 (on
the 0.24 raster). Ours set it in the sans clone's 1.15 em: p48's
fact-sheet heading and table stand 1.4 to 5pt high.
Built: the face's own line and baseline; the table within 0.2pt,
bug59058 91.7 -> 92.2%. Next parting p49 ("Béatrice Lauby-Secretan").

### T22. bug57031: math letters are boxes on Linux — DONE (2026-10-15)
Owner: session starling-office1-df (Linux dev box), from 2026-10-15
Documents: bug57031 (87.0% on Linux).
Known: its formulas are runs of Mathematical Alphanumeric Symbols
(𝑆 U+1D446, 𝛼) in Cambria Math; on Linux nothing named draws them, so
they print as missing-glyph boxes and their lines read as nothing
(p2 "Sti±z1−α/2∙seSti", p3 "H0:S1(t)=S2(t)…"). Placement already
matches Word's to 0.3pt.
Built: math faces among the Linux fallbacks; 87.0 -> 87.3%. Its next
parting is p11/p12's two-line "Note:" row (the Windows box's lead
below; parted rows are the Mac's).

### T23. Endnotes are not set — DONE (2026-10-15)
Owner: session starling-office1-df (Linux dev box), from 2026-10-15
Documents: endnotes (92.9%), Bug54849 — the two with a real endnote.
Known: endnotes.xml is kept for the save and never drawn. Word sets
them after the body's last paragraph: the separator (a 144pt rule at
426.1 in endnotes' print) and the note ("i XXX", the mark in the
endnote numbering's lowerRoman).
Built (office.md): set after the last paragraph when they fit on its
page. Bug54849 95.7 -> 100%. Left: a superscript's raise (Word's 0.36-
0.37 of the full size, ours 0.3) — endnotes' "i" and its body mark.

### T24. A superscript's raise in Word — DONE (2026-10-15)
Owner: session starling-office1-df (Linux dev box), from 2026-10-15
Documents: endnotes, footnotes, table_footnote, Bug54849, bug65649,
form_footnotes (every note mark).
Known: Word's prints raise a superscript 3.6pt over 10pt text and 4.08
over 11 and 12pt (Calibri and Times alike, 51 marks): 0.355 of the
full size within the 0.24pt raster. Ours raise it 0.3 of it, as
measured on PowerPoint's page.
Built: 0.355 under Word's rules; marks within 0.07-0.26pt. Still
open: endnotes' body paragraph holding its mark stands 1.6pt low.

### T25. A paragraph holding a note mark stands low — DONE (2026-10-15)
Owner: session starling-office1-df (Linux dev box), from 2026-10-15
Documents: endnotes (its "A pendant worn…" paragraph, 1.6pt low).
Known: a superscript run makes the paragraph's runs unequal, so it
gets no strut and no baseline correction (`_inkShift`): the engine's
even share of the 1.15 multiple's extra stands its lines low; the
paragraph's height is right (the next one is in place).
Built: such a paragraph takes the correction; within 0.2pt, no score
moved anywhere.

### T26. PageSpecificHeadFoot: a footer's floating table — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: PageSpecificHeadFoot (p2's footer, the Windows box's lead).
Known: the footer's page-number table floats (`w:tblpY` 1 twip, anchored
to the text); Word lays it over the footer's line, which stands where it
would with no table. Ours laid the table in the flow above the line.
Built: in a header or footer such a table takes no room; 90 -> 100%.

### T27. tika-3388: an icon's caption in empty boxes — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: tika-3388 (an attachment icon's EMF caption in MS Gothic).
Built: a metafile's text takes the documents' fallback faces; 50 -> 100%.
Looked at and left the same night: 60329 (0%) is Word printing a
landscape-sized page with no `w:orient` onto portrait paper, its sides
cut (office.md, "one attribute: landscape"): a print artifact, not a
layout to copy. rtl (0%) is Arabic in Times New Roman, which this box
has no face for, and our PDF writes right-to-left runs in visual order
where Word's reads in logical order, so no line matches by its text.

### T28. drawing: a block's margins under a banner — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: drawing (p15, an article 4.4pt high).
Built: a paragraph naming an HTML block (`w:divId`) takes the block's
top and bottom margins; 82.5 -> 86.7%. Still off: p9-p11 (the "Cbonds"
article, tables nested three deep: T9's limit) and p1.

### T29. A cell's paragraphs share their spacing — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: drawing (p1, two headings in a cell 3pt apart too far).
Built: between paragraphs of one cell, the larger of the space after and
the space before alone, as in the body. Five documents up, zh-06c46ba9
down 2.3 (its drift from p41 on lands differently; see office.md).

### T30. Bug51170: the footer's page number at the wrong side — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: Bug51170 (every page's footer), zh-457a8d62.
Built: a floating frame of no stated width is set at the side it is
aligned to; both 100%.

### T31. A merged cell centred over rows that part across pages — DONE (2026-10-16)
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box), from 2026-10-16
(taken at the Linux session's request).
Documents: zh-91e44bcb p4 ("三、本年度办理结果" 21pt low), zh-84702a67
p8 ("是否存在转包、挂靠行为", continued from p7), zh-90e0cea8 p8 (the
"行政审批各阶段帮办服务内容" column 8.6pt low: half a row), zh-1a3c7aa0
p19.
Known: a vMerge cell with vAlign center whose rows go over a page break
is centred by Word in the part on each page. Ours lifts the text by
half of what the rows left behind would give (`lift` in the paging).
Progress (Windows): 00c7eb5f (rows counted with their rules:
zh-90e0cea8 93.8 -> 96.6), f890c12b (a row of no cells of its own takes
no room — zh-84702a67 from 95pt off to 5; the part of a row that parts
inside the span is counted — zh-abe7e063 -> 100).
Then (Windows, this commit): the span's last row counts its part too,
unless its stated height has no room — zh-6cd1befe's last row
"重污染天气事件" (at least 43.65pt, 33 left) goes over whole, so gives
nothing; zh-91e44bcb 96.4 -> 97.1. And a parting row's centred cells
give the part their own height (zh-84702a67 98.2 -> 100). All four
documents' merged cells now stand where Word's do; zh-1a3c7aa0 p19 is
the parted rows' (its row's part runs to the foot), not this.

### T32. A line parted after a stroke before a Cyrillic letter — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: bug65649 (p69's "ИО102-20/А2М"), form_footnotes.
Built: no break after "/" (and "?", "!", "|", closing brackets) before
any non-East-Asian letter or digit. bug65649 99.8%, form_footnotes 97.7.
Next in bug65649: p122, its lines 3-4pt under Word's from "сотрудниками
объекта единовременно." on (not looked into).

### T33. bug65649: a list number's size sets its line's height above only — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: bug65649 (p122's "3.1.x." paragraphs, 14pt numbers over
12pt text).
Known: Word's first line of such a paragraph stands 15.72 under the
line above (the 14pt number's height above the baseline) and the next
line 13.8 under it (the 12pt text's depth below). Ours makes the first
line a whole 14pt line (b879226a's zero-width space), 0.45pt deeper:
each numbered paragraph adds that, 3pt by the page's foot.
Built: the number's height above the baseline only, off a line grid;
p122 within 0.2pt. Next in bug65649: p123, around "3.2.1.2." (not
looked into).

### T34. bug65649: a list number's tab passes the paragraph's own stops — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: bug65649 (p123's "3.2.1.x." paragraphs).
Known: a level-4 number ("3.2.1.3.", first-line indent 567, no hanging)
ends at 67.6pt; the paragraph has stops at 284, 709, 1134 and 1843 twips.
Word starts the text at the 1843 stop (177.1pt); ours went to the next
default stop (155.9), and the line held a word more than Word's.
Built: with no hanging indent, the paragraph's next stop past the
number, however far; bug65649 99.9%. Next there: p132, a form of
underscore lines a line higher in ours (not looked into).

### T35. bug65649: a body word wider than the line opens a line of its own — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: bug65649 (p132, "Замечания: " and 142 underscores).
Known: Word sets "Замечания:" alone and the underscores on the next two
lines; ours parts the underscores right after the label, one line
short. c488db0d does this in cells under 150pt only.
Built: in the body too, off East Asian layout, for words of twenty
characters or more; p132 as Word's. Next in bug65649: p140, a table of
switchgear specifications (not looked into).

### T36. bug59058: Lucida Sans Unicode at its own widths — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: bug59058 (p48's "SEER 9 Incidence…" note, two lines in Word's
print and one in ours; pages 49-52 a line off after it).
Known: Word's PDF embeds the face with /Widths for the 41 characters it
set in it (all digits 632/1000; space 316, hyphen 579; lower case 5-37%
wider than Arial's). The stand-in is Liberation Sans at Arial's widths.
Built: those widths as the face's advances (the rest estimated);
bug59058 92.2 -> 100%, all 52 pages.

### T37. shapes-with-text: a group's text boxes apart from each other — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
(the Mac, which built the stacked case in cabe6fad, offline).
Documents: shapes-with-text (its group: an arrow with text and a text
box under it, two stars without).
Known: only boxes stacked at one width are read whole; here the first
box's text is set at the group's left (79.2pt to Word's 164.6) and the
second's is never read.
Built: each box's text in its own column and from its own top;
shapes-with-text 62.5 -> 100%. Not built: boxes side by side whose
texts overlap in height (they still stack).

### T38. drawing: a line holding only a picture is as tall as its text — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: drawing (every article's masthead: p9 and on, 5pt).
Known: the masthead's right cell is tiny pictures and line breaks in
8.5pt Arial — "IMG 0.8x1.5, br, IMG 161x12.8, br, IMG 0.8x2.2". Word's
band is 32pt (three lines of at least the text's 9.8); ours 17, each
line only its picture's height.
Built: a picture alone between breaks, narrower than the line, has its
run's text height; drawing 87.4 -> 89.7%. Still off there: p9-p11's
"Cbonds" article in tables nested four deep (T9's limit).

### T39. drawing: the mark under a flattened nested table takes no room — tried, not kept (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: drawing (p8's foot: three cell-end marks under its nested
"Cbonds" tables are 0.5pt lines in Word's print and 10-15pt in ours, and
p9's first empty paragraph goes over).
Known: the rule of 2026-10-15 ("the mark under a nested table takes no
room") covers nested tables kept as a block; the flattened ones' marks
are ordinary paragraphs. Flattened cells now carry their margins and
spacing (the reader), which the earlier try lacked.
Tried: the reader marked the empty paragraph that ends a cell right
after a nested table, and the layout drew no line for it, its spacing
(the flattened cell's margins) kept. Page 9 went from 21pt low to 5pt
high, page 11 from partly right to 15pt off; drawing 89.7 -> 86.8, so
it was taken back out. Word's print sets those marks as lines in a
0.5pt face, 2.2-4.6pt apart with the margins — not nothing; what sets
their size is not known (the paragraphs say Verdana 8.5). A lab with
Word would settle it.

### T40. zh-06c46ba9 p39: a list heading under a table keeps its space before — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
(T14 is the Mac's; the Mac is offline, and this is one rule of it.)
Documents: zh-06c46ba9 (78.9%; pages 39-46 a line ahead of Word's).
Known: "（二）現況分析" (List Paragraph, numbered, 6pt before,
contextual) under a table whose last paragraph is a List Paragraph
numbered in another list: Word sets it 9pt below the line box (the
table's 3 and its 6), ours 3. Our same-style test holds two numbered
items alike across a cell's edge because their kinds match.
Built: two list items either side of a cell's edge are not alike
(plain neighbours still are). zh-06c46ba9 78.9 -> 89.5%, zh-84702a67
98.2 -> 99.6, zh-abe7e063 98.0 -> 100. Left in zh-06c46ba9: p52-55
(reference lists breaking lines elsewhere; Word starts one with "，"),
p70-72 (T41).

### T41. A paragraph's first-line count in characters replaces its style's hanging one — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: zh-06c46ba9 (p70's division-of-work table, rows 30pt left of
Word's), zh-64044a1d (37 such paragraphs).
Known: style "一" (afb) says hangingChars 200; the cells' paragraphs say
firstLineChars 0 and firstLine 0. The reader keeps both counts, and the
layout reads hangingChars first, so each line hangs two characters out.
Built: naming either count drops both inherited ones; p70's rows at
Word's x. No score moved (the match is by height). Left on p70-72: the
page starts ~80pt higher than Word's, after a group of text boxes on
p69 whose text Word's PDF does not carry (shapes: the Mac's).

### T42. A line of ideographic spaces alone is its mark's line — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: zh-64044a1d (p100, the lead "rows whose cells hold only
U+3000" in the Mac's notes below; costs p100's foot and p101).
Known: reproduced on Linux in a paragraph alone (the table's own style
"．表文", 11pt 標楷體 over Times, on an 18pt line grid): "　" is two
pitches in ours, " " and an empty paragraph one; Word's print sets the
U+3000 rows as the empty ones (18.5). The space rule (spaces set no
line's height) counts U+0020 and tabs only, and U+3000 is set in the
East Asian face, whose 11pt line takes two pitches.
Built: U+3000 counts as a space for the rule, and on a line of spaces
alone is set in the run's Latin face. zh-64044a1d 95.7 -> 97.9%,
zh-90e0cea8 96.0 -> 97.5, zh-84702a67 -> 100, zh-69bbcc3c -> 99.5.
Left in zh-64044a1d: p97's form is a VML text box holding a table, which
the reader skips (tables in text boxes are not read: the only such
document); p17.

### T43. Ruby text (w:ruby) is read, drawn and saved — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: 61470 (0%: "東京" with "とうきょう" over it).
Known: the reader skips `w:ruby` whole, base text and all, so the page
is blank and a save loses it. Word's print: the ruby at its own size
(`w:hps` 11 half-points), its baseline `w:hpsRaise` (20 half-points)
above the base's; the base "東京" spread across the ruby's width
(distributeSpace: 2.75pt between, half that at either end); the line
two pitches of its 18pt grid.
Built (office.md, "Ruby"): read onto the base's style, the base spread,
the line made room, the ruby drawn over it, written back as it came.
61470 0 -> 100%; within 2pt of Word's. Nothing else moved.

### T44. A paragraph's trailing spaces after ideographs take the ideographs' face — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: zh-1563bd74 (the note below; a page long on Linux).
Known: the Mac's lab `hfl` (Word 16, the footer's P2 in the body, four
variants): five trailing spaces after "红河县人民政府发布" in 14pt bold 宋体
make the paragraph no taller (52.56 with them, 52.80 without; 51.12 and
51.36 without the X). Ours sets those spaces in the Latin stand-in
(Liberation Mono), whose depth the line takes: 19.4pt for 18.2.
Built (office.md): those spaces, at a paragraph's end, are set in the
ideographs' face at the stand-in's width. zh-1563bd74 88.6 -> 99.7%,
Word's 29 pages. Spaces within a line left as they were (tried: six
documents collapsed — the line fitting measures them otherwise).

### Note from the Linux dev box (2026-10-16): zh-1563bd74 runs a page long on Linux only — settled by T44
Owner: none — a lead (zh-1563bd74's notes are the Windows box's).
zh-1563bd74 was 88.6% on Linux (30 pages to Word's 29), 99%+ on the Mac. Page
25's last paragraph, an empty exact-28pt line, misses the foot by 0.4pt
in the PDF's units (20 to the point), so "第十章 就业救助" and all after
start a line low. The footer is 0.8pt taller here: its paragraphs are
20.5/38.9/19.2pt on Linux, 20.5/38.1/19.2 on the Mac (measured both
sides). The 0.8 is P2's second line, "红河县人民政府发布" + five spaces in
14pt bold 宋体: 19.4pt where its empty twin (P3) is 18.2. Its ideographs
are drawn by the platform's CJK fallback (Noto Sans CJK on Linux, ascent
1.16 / descent 0.288 em) and its spaces in the Latin stand-in (Liberation
Mono at 5/6, ascent .735 of its line); at one line height of 18.2 each
splits it its own way, and the engine takes the deeper of each side:
14.58 above from the CJK face, 4.82 below from the mono one. The
single-line and on-grid paragraphs already get a strut of the tallest
stretch for this (`_strut(tallest:)`); P2 is two lines (the "X" in 16pt
Calibri, 19.5, on its own) off the grid, so neither applies, and a strut
of its tallest would set both lines at 19.5. What would settle it: a line
of a square face's ideographs with Latin in it, off the grid, in a
paragraph whose other line is taller — Word's height for each line.

### Leads from the Windows box (2026-10-16, measured, not built)
- Lab `ps`: built (a picture wider than its line keeps the break after
  it; before 2013's layout a space after it opens a line) — zh-9c5d0c3f
  p4. Left: ours sets the paragraph under a picture and a space 2.8pt
  lower than under the picture alone in mode 15; Word sets both alike.
- zh-454e2e29 p4: the diagonal header cell's "人數", "官等", "類別" are
  text boxes anchored in the cell (with two `wps` line shapes, not
  drawn): ours 8pt high. Shapes and text boxes — the Mac's.
  (Linux, 2026-10-16, 82e6e51d: drawing groups and lone shapes the
  outline skipped are drawn now — every preset, theme and system
  colours, arrowheads; one of this cell's diagonals shows. The labels'
  8pt is untouched.) Both diagonals draw now; labels: T54.
- zh-1563bd74's footer (for the Linux note under "Note from the Linux dev
  box"): its height is right as ours has it. Lab `ft` (Word for Windows,
  the document's own footer): the page number stands at 112.6 and "红河
  县人民政府发布" at 72.7 whether the FAFAFA "X" (which Word's PDF carries
  no text for) is there or not, 40pt apart — ours 113.2 and 73.7, the X
  on a line of its own. Setting the X and the text as one line made the
  footer a line shorter and moved every page (tried, reverted). The p26
  loss is elsewhere. (Also tried: measuring `w:firstLineChars` by the
  first run of text past an anchored shape, 320pt there as its
  `w:firstLine` says, not our 180 — it cost zh-9dd9ce6d 100 -> 15 and
  zh-1563bd74 88.7 -> 10.5; reverted.)
- chartex: our pages match Word's three now; left are a stock chart
  (`c:stockChart`, drawn as a grey box) and the two `cx` charts, whose
  fallback pictures carry no text for the line match. 61745: a bar
  chart's category labels step 59.3pt to Word's 57.7 (plot area).

### T32. A parted row's part on its page: its height and its centred cells
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box), from 2026-10-16
(the Mac's parted rows; the Mac sessions are offline and the Linux box
asked — Mac, say so here and I stop).
Documents: zh-15728c84 p3 (row 9), zh-1a3c7aa0 p22 (row 65), p32 (row
111) — see the parted-row notes under "Note from the Windows box
(2026-10-15, night)".
Known: Word's part ends under the last line kept on the page and is no
shorter than the row's stated height; centred cells stand centred in it.
Progress (Windows): the centred cells now stand so (zh-15728c84 96.0 ->
98.5). Left: the part's rule still runs to the page's foot, and
zh-1a3c7aa0 p22/p32 (their rows' heights there).
2026-10-16 (a980bef8): the part's rules end with it, and merged centred
cells beside it centre over a part no shorter than the row's stated
height — zh-91e44bcb 97.1 -> 100 — except where a cell merged down from
above runs its text below the part (zh-e6d54ae4). Left: zh-1a3c7aa0
p22/p32.
zh-1a3c7aa0 p57 (row 170, every cell centred, "限制新建氟化氢…" 3 lines
of 31.2 parted 2+1): Word's part is 70.8 to the body's foot, 重点监管…
(2 lines, whole) 4.2 down, "170" centred, and the cut cell's 2 lines
8.4 down — at the part's bottom, as if centred over both parts (p58's
part 39.6 = 31.2 + 8.4). Ours: part 62.65, the cut cell at the top.
Tried "a centred cell that parts: part to the foot, its lines at the
bottom": p57 unchanged and zh-1a3c7aa0 (13 pages), zh-15728c84 p3,
zh-91e44bcb, zh-84702a67 worse — reverted, not the rule.
zh-4d143b5e (the Mac's second sample, its lead): a row parting under
centred cells merged down over six rows went over whole; a merged cell
now parts from its text's start as a cell of its own row does — 36.5 ->
99.8.
zh-f59a76e9 p17 (98.4%, second sample), measured and left: Word parts
row 70 ("A090370 政府举办的公益性人才交流活动的组织与实施服务") at page 17's
foot, its band 158.0 -> 100.7 there and "服务"/"组织与实施" opening page
18; ours sets row 70 whole (157.9 -> 128.5) and parts row 71 under it
with nothing of it on page 17, so the merged "基本公共服务事项" and
"人才服务类" centre over a span 28pt shorter and stand 11.5pt high.
Which row Word parts there is the open question.

Note from the Mac (2026-10-16): zh-799c91cd 96.8 -> 95.6 between the
n225 and n230 sweeps. Page 6's table, whose last row runs to the foot,
now ends at 84.8pt above the page edge where it ended at 85.0. The
empty paragraph after it (one space, 12pt 標楷體) no longer fits under
it and opens page 7 instead, setting all of page 7 14pt low. Word keeps
it on page 6. Reverting 8cc05b33 changes nothing. Of the commits in that
window this is a parting row's height, so 10a54e42 or 94ac7235 is the
likely one; not bisected.
### T43. bug57031 p11: a SAS table runs 2.7pt short, a "Note:" row parts — DONE (2026-10-16)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac, has Word), from 2026-10-16
Built: a separated table (cell spacing stated, 0 too) is framed by its
own top and bottom lines, and the frame takes room, even where every cell
turns its sides off (`frame` in the cell geometry). bug57031 87.0 -> 94.1;
nothing else moved.
Documents: bug57031 (87.0%). Known (office.md, leads of 2026-10-15): the
gaps between its stacked HTML tables run short, not its rows (Word's rows
alternate 21.1/21.4, ours 21.3); by the foot of p11 ours has room for one
line of the two-line "Note:" row that Word carries whole to p12.

### T44. zh-a4b0f6ea p20: a page-anchored floating table Word breaks after its first row — measured, released
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac), again from 2026-10-16 — with zh-6cd1befe p51 (a 26-row
page-anchored table: Word sets its header row alone on p51, the rest on p52; found by starling-bd)
Built (partial): a page-anchored table (`TableStyle.pageAnchored`) that
does not fit whole where it stands keeps its first row there and goes on
at the next page's head — zh-6cd1befe's p51/p52 now part where Word's do;
no score moved (its title and header stand ~20pt higher than Word's,
which sets the table at its tblpY, and its p52 rows run 30pt to Word's
25). zh-a4b0f6ea is untouched: its table fits whole in ours, and the
paragraph before it (labs fa-fd) is what makes Word part it. Open: the
table at its tblpY; that paragraph's part.
Labs `fa`–`fd` (the document's last section alone, Word 16): as is, page 1
holds the header row and "单位（盖章）" below it, the rest on page 2 —
reproduced. Without the "单位（盖章）" paragraph that stands before the
table, the whole table stays on page 1; anchored to the text instead of
the page, likewise; without its merged cells, the same split. So the
paragraph before a page-anchored table (which the table overlaps, and
which Word sets under the table's first row) is what makes Word part it
there — the mechanism is not found.
Documents: zh-a4b0f6ea (88.6%). Known: `tblpPr vertAnchor="page"`; Word
prints only the header row on p20 and the rest on p21, with the text
under the table still on p20.
Built (2026-10-16, labs `fa2`–`fd2`: the roster's title, "单位（盖章）" and
the table alone, its tblpY 3668, 6000, 1800, and without the line): a
page-anchored table now stands at its tblpY (`TableStyle.pageOffsetY`),
and body paragraphs before it on the page that reach into it are set
again under it — Word's `fc2` (tblpY at the margin) has the title and the
line under the table; `fa2` keeps them above (header "姓" at 228, ours 229).
zh-a4b0f6ea 88.6 -> 88.9 ("单位（盖章）" now at 423 as Word's), zh-6cd1befe
97.8 -> 98.2; nothing else moved. Still open: Word parting the roster
after its header row on p20 (ours keeps it whole and runs past the foot).

### T50. drawing: the mark under a nested table at half a point, a short picture's line its mark's — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: drawing (p8's foot, p9-11: 85 lines).
Known: Word's print (clipped text kept) holds exactly five spans of
0.48pt — Verdana four, Arial one — and the file has exactly five empty
paragraphs that end a cell right after a nested table (their marks say
8.5pt). So Word sets those marks at half a point, not at nothing (T39's
try, which overshot) and not at their size (ours). Plan: the reader
flags such a paragraph (layout only, not saved), the layout sets its
line at 0.5pt; the flattened cells' margins stay.
Built (office.md): the marks at half a point, and — what that uncovered
at page 9's top, settled by the Mac's lab t50 — a paragraph of a picture
shorter than its mark's single line takes that line, the picture at its
foot. drawing 89.7 -> 98.1%; nothing else moved. Left: p11's 16 lines.

### T51. Space shared across a hidden paragraph — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: drawing (p11's last 16 lines, 12pt low from "ИА Regnum").
Known: between "…ОАО "ПО Водоканал г. Ростова-на-Дону"." ("text": 14pt
after, auto) and the heading "ИА Regnum" (12pt before) stands an empty
paragraph whose mark is hidden. Ours hides it, but the space after and
the space before no longer share across it: ours 40.75 baseline to
baseline, Word's 28.8.
Built (38a62adb): the space a paragraph shares is the nearest shown
paragraph's above it. drawing 98.1 -> 100%; nothing else moved.

### T52. Print markup as Word does: comment and change balloons in the margin — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16 — the user's call: keep Word's behaviour
Documents: 58067, Tika-792, delins, comment, testComment, WordWithAttachments
(all near 0%: Word's references are prints with markup).
Known (the Windows box's note below): the page drawn at a scale k, 8.3pt
from the paper's left, a grey balloon pane ~188pt wide ending ~18pt
from the paper's right (letter k 0.729, pane 407.5-594.5; A4 k 0.7367,
pane 387.0-576.6), centred top to bottom; balloons "Commented [s1]: …",
"Deleted: …", "Formatted: …" in ~6.5pt, level with their anchors.
Built (office.md): the frame, comment, deletion and formatting balloons,
deleted text out of the page. comment, testComment, 58067 -> 100%,
delins 23.3, WordWithAttachments 23.7 (their bodies' own layout now
shows: delins's lists, WWA's header and table). Not built: moves
(Tika-792), "Field Code Changed", change bars.

### T54. zh-454e2e29 p4: a diagonal header cell's text-box labels 8pt high — DONE (2026-10-16)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb (Mac, has Word), from 2026-10-16
Documents: zh-454e2e29 (95.3%). "人數", "官等", "類別" are text boxes
anchored in the cell, beside two `wps` diagonal lines.
Built: a floating text box's text takes the document's line grid, as
Word's does (not `w:combine` text, a box in the line). Labels within
0.4pt of Word's; no score moved (the line match groups that row alike).
Linux built the same at the same time; merged as each box's own section's
grid (zh-6cd1befe's flow chart is in a section of none) and inline boxes
too. On Linux zh-454e2e29 94.8 -> 96.7%; nothing else moved.

### T55. Web spacing between two lists (numbered T53, then T54, at first; the Mac's came first) — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: delins (its body under the markup).
Known: delins's bullets are web-spaced (before/after 100 with
beforeAutospacing/afterAutospacing). "A name in various Indian
languages…" (numId 1) and the nested "the subcommentaries…" (numId 2)
stand 19.1pt apart in Word's print (scaled; 27.6 unscaled), 10.3 in ours:
Word gives 14pt between items of two lists, ours none, the two being the
same kind. The same after a list's last item under a paragraph of none.
Built: one list is one numbering (listId) where the file names it; an
item's automatic space after is none only before an item of its own
list. bug57031 94.4 -> 100%, delins 23.3 -> 35.0; nothing else moved.

### T56. A Symbol bullet's line at the bullet's own size — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: delins (each bullet's first line 1.5pt taller than Word's).
Known: the level's face reaches a list line through a zero-width space
in it (form_footnotes' Symbol bullets, 12.24pt lines under 10pt text);
that space takes the text's size, not the level's: delins's 10pt Symbol
bullets under 12pt Times make a 14.7pt line where Word's is 13.8.
Built: at the level's own size where it says one. delins 35 -> 50%;
nothing else moved.

### T57. zh-90e0cea8 p1: the standard's cover — its "37" logo frame and ICS/CCS lines — measured, released
Owner: none — released by 011ZXp8eXomzYegGkuu7484P (Windows box), 2026-10-16 (handed over by the Mac, 011uWpmC)
Documents: zh-90e0cea8 (p1: 5 of 10 lines).
Known: 9c6cc3ca (margin-anchored frames at their y) and 7d14992b (a frame
naming a y and no anchor is on the margin) put the cover in Word's order.
Left: "ICS"/"CCS" (a page frame at y 568 twips, style "header" on Normal's
exact 20pt line) stand 7.6pt high, baseline 30.55 against Word's 38.16;
"37" (framePr yAlign="inline", vAnchor margin, hAnchor text, w=0, over a
style frame at the margin's x 6748 y 171; a logo picture and 54.6pt bold
"37") 33pt low, 122.0 against 88.56, Word's logo at y 57-88; the title
4pt low; "发布" 4pt low.

Labs `cov/cA`-`cF` (Windows box: the cover's first 4, 5, 6 and 10
paragraphs in the document's own package, its first section; top margin
-338, 338 and 1440 twips): Word for Windows sets ICS, 03.080, CCS and
"A 12" on four lines (38.16, 51.0, 65.76, 80.76) whatever the margin —
not the Mac print's two ("ICS 03.080" at 38.16, "CCS A 12" at 54.0) —
and moves "37" with what follows it (128.5, 198.4, 249.1). Ours sets the
labs' four lines within 0.8-3.1pt of Windows Word's, but in the whole
document joins them in twos and sets them 7.6pt high. Word for Windows
and for Mac disagree on this cover, so a Windows lab cannot settle it;
needs the Mac's Word.
### Note from the Mac (2026-10-16 night): the zh corpus is 88 documents now
12fef482 adds a second seeded sample of 20 zh documents, with Word's
prints. It started at 74.5% of Word's lines, against the first 68's 98%,
so new gaps are there. A sweep's zh mean is not comparable across that
commit; compare per document. Being worked: zh-4d143b5e's merged-cell
row parting (Windows, T32), zh-2a241df1's charts (Mac, T59).
- zh-3c055c9b (44.9%, mode 15, linesAndChars grid of 17.0pt at 16pt,
  zh-TW, compressPunctuation, the body style's `w:kern` 0): p2's line
  "第2頁】，於113年4月29日辭職【附件2，第5" takes "頁】，" in Word's print,
  33.7pt over by our measure. Word squeezes marks all along the line
  (職→【 11.7, 】→，9.0, ，→於 14.3; an ideograph is 17.0). Ours: "need
  33.68 room 74.4 of 6 marks taken false". The mode-15 test's stretch
  term counts the line's ten or so digit autospaces whole, and that
  fails it. Tried and reverted (Mac): (1) closing up mark pairs without
  `w:kern` (zh-3c055c9b 44.9 -> 61.7, but zh-17749c13 85.6 -> 53.7 and
  nine others down); (2) leaving the autospaces out of the stretch on a
  character grid (zh-3c055c9b -> 13.1). Released: it is the grid
  fitting the Linux session built. A lab of this line, with the over
  varied, would say what Word counts.

### T62. A table nested in a parting row parts between its rows — DONE (2026-10-16)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac), from 2026-10-16
Documents: zh-d35cbbdb (55.4%, second sample). Its body is one cell of a
page-long layout table; the consent table nested in it starts at page
4's foot. Word sets its header row there and the rest on page 5; ours
took the nested table over whole (a nested table is one block to the
row's cuts), and every page after ran a block behind.
DONE: a nested table's row bottoms are cuts of its cell (`cellCuts`):
zh-d35cbbdb 55.4 -> 88.9, nothing else moved. Left: the header's "項目",
merged down into row 2 and centred over both, is not drawn on page 4
(Word's is, at the row's middle).

### Footer trailing spaces in a right-aligned paragraph (zh-c5b5087b, zh-9dd9ce6d) — measured, released (Mac)
Both footers share zh-1563bd74's build: a page-number box on an empty
first paragraph indented past the column, then a right-aligned (`wordWrap`
0) paragraph of an invisible FAFAFA "X" or "嘉" with spaces, the publisher's
name, and five trailing spaces, then an empty paragraph. Measured from
Word's prints: in a right-aligned paragraph trailing spaces take room.
zh-9dd9ce6d's second line, two leading 8pt spaces, "嘉峪关市人民政府发布"
(14.25 a character) and five trailing spaces, is 201.3pt of its 202.85
and stays one line. zh-c5b5087b's thirteen characters with five spaces
do not fit: four spaces go to a line of their own, the text stands 14.5pt
left of the margin, and the page number 18pt higher (Word 128.7, ours
110.8). Tried (Mac): a word joiner after a right-aligned paragraph's
trailing spaces, so the engine gives them room and wraps what does not
fit. zh-c5b5087b 84.7 -> 94.4, but zh-9dd9ce6d 100 -> 89.9: ours wraps
its last space, so our line is a few points wider than Word's 201.3.
Our natural width of that paragraph traces as 421pt, where its glyphs
come to about 200, so something unseen is counted. Find that first,
then the joiner is the fix. Released.
Found and built (01Xgpbk5, Mac, 6a5f56b7): the unseen width was the
trailing spaces themselves — set in the ideographs' face (kind -2), their
spacing carries the stand-in's width, and the half-em rule counted it
twice (13.3pt each, Word's 7.15). With that, the joiner holds: page
numbers 713.0 (Word 713.3), 728.6 (729.4), 727.3 (727.9). It replaces
19599caf's held spaces (Linux, 017F2), which held on Linux but on the Mac
set these footers a point taller and cost zh-c5b5087b and zh-1563bd74 a
page each. Mac: zh-c5b5087b 28.6 -> 94.4, zh-1563bd74 88.9 -> 100.
Awaiting a Linux sweep of 6a5f56b7.
Built (Linux, 19599caf, at the same time): the trailing spaces after an
ideograph in a right-aligned paragraph set as held (no-break) spaces,
each after a zero-width break, at a space's width set outright (the
unseen width was the held spaces' spacing counted twice, and an ideograph
face's no-break space being an em), the breaks in the ideographs' style
so a line of spaces alone is a text line. zh-c5b5087b 83.7 -> 93.9 (its
footer within 0.6pt of Word's), zh-9dd9ce6d unchanged at 99.6 and still
one line (its "嘉峪关…" 17pt right of Word's now, 52 before: the two
leading spaces and the "嘉" Word keeps on that line are left), zh-1563bd74
100 with its text within 1pt. Not after Latin text (zh-7dc3afad's
right-aligned figures hang their space in Word's print).

### Note from the Mac (2026-10-17): Word's 楷体_GB2312 changed between the two samples
A fresh print of zh-78729cf9 today (Word 16.113.3 / 26092714, macOS 27.0
26A428, the same OS build as both samples' PDFs) sets all its 楷体_GB2312
text in Microsoft YaHei. The corpus print of 2026-10-12 has 545
characters of it in KaiTi. So the first 68's KaiTi was Word's state then,
perhaps a cloud font it had downloaded. The second sample (2026-10-17)
reflects today's Word: YaHei. One rule cannot match both; reprinting
the first sample is the user's call and has not been done.

**Reprinted (Mac, 2026-10-17).** All 68 of the first sample's prints
were redone with Word 16.113.3. That commit changes references only. Old
KaiTi is YaHei in every print that had it, and zh-64044a1d also lost
STHeiti. Same build, scored on the Mac against old and new references:
zh 95.6 -> 95.4, 73 -> 71 at 95% or more. Five documents moved:
- zh-15728c84: 98.0 -> 86.4
- zh-232090e0: 97.8 -> 90.5
- zh-37b6536f: 97.7 -> 96.9
- zh-64044a1d: 97.1 -> 97.0
- zh-69bbcc3c: 99.1 -> 99.0

The OfficeFonts mac rule 楷体_GB2312 -> KaiTi now goes to YaHei; that
change is lenovo-3's (Linux).

### Leads from the second sample (Windows box, 2026-10-17)
Done here: zh-4d143b5e 36.5 -> 99.8 (6ef30c71), zh-b13d0fb4 93.5 -> 100
(b9952df9). Measured and left:
- zh-e02b0479 (68.6%): its form's last row is two 15.6pt grid pitches in
  Word because its text, 楷体_GB2312 10.5pt, is YaHei there (an 18pt
  line); our 楷体 is KaiTi, one pitch, and the merged "所需信息情况" above
  centres 6pt high. The 楷体_GB2312 question above — not to build alone.
- zh-f39e54b6 (94.6%): a one-cell borderless table, tblW 8820 on a text
  width of 8306 (mode 14, tblInd 108, the cell 5000 pct): its lines end
  at 524.5pt in Word's print, 531.0 in ours (the left edges agree, 146.6
  and 146.7), so ours takes a character more on some lines. The rule for
  an over-wide table's right edge in mode 14 is not found. (Lab `sq14`
  on the way: Word takes a character exactly half an em over — 7.0 at
  14pt — and leaves it at 7.05; our legacy squeeze agrees.)
  Linux, 2026-10-17: Word's right edge on page 2's full lines is 530.8,
  ours 531.0, so the over-wide table is not it. The misses are lines on
  the half-em threshold: article 24's first line takes "縣" 6.9993pt over
  in ours (`STARLING_RICHTEXT_FIT`, column 370.0); in Word's print the
  line starts 89.88 (ours 90.0) and ends by 530.8, 0.08pt narrower, so
  its "縣" is ~7.08 over and goes down. Where Word's 0.12 and 0.2 come
  from (twips rounding of the cell's or the chars-based indents?) is
  what is left.

### zh-f0bd9ea8: punctuation squeeze on a grid narrower than the ems — measured, released (Mac)
Mode 14, linesAndChars charSpace -842 at 16pt (Normal 10.5). Done: the
balanced half-width spaces' grid share (57849075). Left: every body line
takes one character more than Word's ("…工程品" + "牌" 5.1pt over, "，"
the one mark to give). zh-d68ac84a (charSpace -5544) agrees: Word leaves
"增" (7.3 over, one mark), "土" (6.7, one mark) and "50" (11.0, one mark),
and takes "政" (7.3, three marks) and "质" (3.1, five marks). But it
leaves "原" (3.8, two marks). Tried and reverted: no squeeze at all on
such a grid (d68ac84a 98.8 -> 35.4); none for a character or a word
(-> 47.9); none with one mark (d68ac84a -> 93.9, f0bd9ea8 only 53.6 ->
54.3). Lab `cg1`/`cg2` (this package): the grid's -0.21 applies at every
size, and the text's size against Normal's changes nothing. A lab of
one line with one, two and three marks, the over varied, would say what
Word counts on such a grid.
Lab run (Mac, 2026-10-17, ~/starling-word-check/lab/tools/squeezelab.py:
one justified or left line of 仿宋_GB2312 — Word's YaHei — the first 24
characters holding 1, 2 or 3 "，", the over bisected to 0.12pt by the right
margin): on charSpace -842 at 16pt (pitch 15.75) Word takes the 24th only
within 0.12pt, whatever the marks — no squeeze, f0bd9ea8's case; on -5544 at
16pt (pitch 14.65) within 4.0-4.12pt, the same for 1, 2 and 3 marks; on
-5544 at 12pt and -2800 at 16pt, within 0.12. So it is no count of marks:
something of 16pt on the -5544 grid gives about 4pt (3 x the grid's 1.353?
the others do not follow). Not built; free.

### T59. A column chart with a line on a second value axis — DONE (2026-10-17)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb (Mac, has Word), from 2026-10-16
Documents: zh-2a241df1 (7.6%, from the Mac's second Word sample of 20
unprinted zh documents: prints in ~/starling-word-check/zh2, scored with
DOCX_WORD_REFS). Its two charts are `c:barChart` plus a `c:lineChart` on
its own axes (a percentage axis on the right). `ChartXML.read` takes a
combination only on one pair of axes, so both read as nil and nothing is
drawn. Plan: read the line's axes, scale the line by its own axis, and
label that axis on the right (Slides' ChartPainter, shared with decks).
Done: the second axis (ae2d227a). The caption under a table is one
pitch, because spaces beside text add no height (2026-10-17). That was
page 2 on, 35.2 -> 72.4. The data table is drawn (369e2840): 72.4 ->
93.3. With Slides' ten-step axis (cf320772) it is 97.1. Left:
- chart 1 stands 2.5pt low, an inline object on the grid;
- the style-2 fills.

DONE (2026-10-17).

### T58. A paragraph that opens with a tab: the line stays at its indent — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: WordWithAttachments (its header's "<tab>Страница 1", centred
on a stop at 233.85pt, stands 101pt right of Word's).
Known: a tab is widened by spacing on the tab itself, and the engine sets
a character's spacing half before it: at a line's start that moves the
whole line on by half the tab. Slides put a leading tab's widening into
the first line's indent box (HowWeRefactor's quotes); Word's paragraphs
do not yet. With a letter before the tab the line is right.
Built: documents too. The header within 2.4pt of Word's; no score moved.

### T60. Moved text is read, kept and printed — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: Tika-792 (0%; its "Moved (insertion) [1]" balloon).
Known: the reader skips `w:moveTo` and `w:moveFrom` whole — moved text
is gone from the page and from a save. Word shows the new place as an
insertion (and prints "Moved (insertion) [n]" beside it), the old one
as a deletion.
Built: `w:moveTo` reads as an insertion and `w:moveFrom` as a deletion,
both marked moved, so the text is on the page and survives a save (as
w:ins/w:del). Printing labels the old place "Moved down/up [n]:" and the
new one "Moved (insertion) [n]". No score moved: Tika-792 still 0 — its
move balloon prints, but Word's "Formatted: Font color: Auto" and the
balloon order still differ.

### T61. delins's balloons: a reformatted paragraph mark, deleted list items — DONE (2026-10-16)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: delins (55%).
Known: Word gives a reformatted paragraph mark its own "Formatted:"
balloon (each link item: Field Code Changed, its text's, its mark's);
ours prints none for marks. In a deletion's balloon Word starts each
deleted paragraph on its own line, a list item's with "<#>"; ours runs
them on ("Tika.¶Tika Waylan").
Built: both, and a field's ends break a "Formatted:" stretch while a
reformatted mark joins the next paragraph's (read off the connector
lines in Word's print). delins 55 -> 75%, nothing else moved. Open:
which of a link's balloons comes first (office.md).

### T63. A 1.5-spaced line at a page's foot: does its extra space count? — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-16
Documents: zh-8112041b (70.8%, new sample; 標楷體, which both samples
print in YaHei).
Known: page 2 matches Word's to 0.3pt line by line, then Word keeps four
empty 1.5-spaced paragraphs (36pt each, 24 of it the line) under article
nine and ours three: the fourth's line box runs about 5pt past the
margin, its text does not. Word sets the extra space of a multiple
spacing below the text. Try: let that extra hang past the foot as the
grid's half leading does (`_overhang`), and see what the sweep says.
Built: that, and a page break inside a table cell is nothing (the
form's title cell opens with two; ours split an empty line off, 59pt
of the page). Mac measured the same independently. zh-8112041b 70.8 ->
100%, nothing else moved (same-base sweep with and without).

### T65. zh-17749c13 p20: a grid line's limit at the page foot is its deepest face's — DONE (2026-10-17)
Owner: session 01Xgpbk5jLzrCcB28yZBzYHN (Mac), from 2026-10-17
zh-17749c13 (85.6%) runs a line ahead from page 21: ours keeps "第六十六条
申请办理船舶国籍证书…" (14pt 宋体, one line, two 15.6pt pitches, auto
spacing) at page 20's foot, baseline 763.5; Word sends it over. Labs `p0`–`p7`
(page 20's text alone, the bottom margin 1440 down 20 twips a step):
Word keeps it from 1420 on, so its limit is a foot between 770 and 771pt,
6.8–7.8 under the baseline. Ours lets a grid line overhang by half its
extra (`gridOverhang`, 6.5 here, from lab `gf2`'s YaHei bold on an 18pt
grid), which puts the limit near 767 and keeps it at 770. Neither the
natural bottom (~767) nor the line box (~774) is Word's here: 宋体 on a
15.6 grid needs labs at more sizes before the rule changes.
Measured (lab `footlab`, Word 16, one-page labs bisecting the bottom margin
to 0.25pt): the foot must lie under the last line's baseline by 0.294 em in
宋体 (12, 14, 16, 22pt: 3.5, 4.0, 4.75, 6.45) and 0.465 em in 仿宋_GB2312,
which Word sets in YaHei (12, 14, 16pt: 5.5, 6.7, 7.4) — each face's natural
line below its baseline; the same with 14pt of space after, auto or not.
zh-17749c13's line is 宋体 bold and YaHei: YaHei's 6.7 decides, and ours
took its overhang from the first run's 宋体 (6.5) and kept the line.
DONE: a text line's overhang is its runs' least (`_overhang`): zh-17749c13
85.6 -> 98.1, zh-2a241df1 72.4 -> 74.3; nothing else moved.

### T64. 楷体_GB2312 is YaHei in today's Word for Mac — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: the zh corpus. Word 16.113.3 sets 楷体_GB2312 text in
Microsoft YaHei (all seven of the second sample that use it, alt name
or not; zh-78729cf9 reprinted today: 8152 YaHei characters, no KaiTi),
where the first sample's prints of 2026-10-12 have KaiTi. The Mac
(011uWpmC) is reprinting all 68 of the first sample as one
references-only commit. Then: `OfficeFonts`' mac rule takes
楷体_GB2312 to YaHei, swept against the new prints on Linux.
Built: against db1a7940's prints, same base with and without, Linux:
zh-e02b0479 68.6 -> 97.1, zh-15728c84 86.9 -> 98.5, zh-232090e0 86.7 ->
95.6, zh-69bbcc3c 99.4 -> 99.5; nothing down; mean 91.25 -> 91.49.

### T66. zh-15428325's bold "（一）" lines: one character more than Word's — tried, released
Owner: none — released by starling-office1-df (Linux), 2026-10-17
Documents: zh-15428325 (94.1%; its bold "（一）…" lines take a character
more than Word's).
Known: under `w:balanceSingleByteDoubleByteWidth` ours spaces every
full-width character twice (16pt at -0.3 set 15.4 apart). Word's prints:
twice for 仿宋_GB2312 and 標楷體 (YaHei stood in: zh-6cd1befe 15.4 and
11.0, zh-9c5d0c3f 10.0), once for a face Word has (zh-15428325's 仿宋,
15.68), and zh-232090e0's 楷体_GB2312 once (11.8) in the KaiTi print of
2026-10-12, twice (11.6) in the YaHei reprint. Try: double only where
the East Asian face is a stand-in.
Tried and reverted: doubling only in a stand-in face took zh-15428325
94.1 -> 60.7 (and four others down a little). The 15.68 read off its
print is a justified line's, stretched: its natural spacing may be
doubled after all. What the fitter sees for "（一）使用房票基础奖。各主体已推行
房票安置的，房票奖励" (`STARLING_RICHTEXT_FIT`): "励" 7.49pt over, inside
the half-em 8.0, taken; Word sends it down. Measured differences, not
enough together: Word's first-line indent is 30.95 (the file's 619
twips; ours 2 x (16 - 0.6) = 30.8), and its bold is ~0.03pt a character
wider than our fake bold (0.31 over plain against 0.28) — ~7.97 over.
Also seen: every line with letter spacing starts 0.3-0.8pt left of
Word's — the engine sets a character's spacing half before it (as for
tabs, T58), Word after. A lab of this line, the over varied, would say
what Word counts.

### T67. A comment's balloon hangs at the comment's end — DONE (2026-10-17)
Owner: session starling-office1-df (Linux dev box), from 2026-10-17
Documents: WordWithAttachments (23.7%).
Known: its comments each span a quatrain. In Word's print the balloons
"Commented [v2]" and "[v3]" are level with the quatrains' last lines,
where the comment references stand; ours with their first. Word also
prints no balloon for v1, whose reference is alone in an empty
paragraph, yet numbers the others from 2 — not modelled (one file).
Built: anchored at the range's end. Each balloon now 2pt under its
anchor line as in Word's (v2 445/447 there, 389/391 ours); no score
moved — the page is still ~56pt high for its missing attachment icons
and the unframed text box.

### T45. zh-2b955411 p26: 9pt text over a 26pt paragraph mark sits 5pt low in Word — measured, released
Owner: — (released by session 01Xgpbk5jLzrCcB28yZBzYHN, 2026-10-16)
Labs `mk1`, `mk3` (Word 16, the document's package): a 26pt paragraph mark
under a 9pt line changes nothing — off the grid, on its 28pt grid, in the
body and in a centred table cell beside an empty cell of the same mark;
ours matches each to Word's 0.24pt raster. So the mark's size is not the
5pt; what else the row holds (style a3, the empty cells' 1040 first-line
indent, the row's own height) is the next thing to vary.

### T46. The letterhead rule 1pt low (zh-e37f8d40, zh-9dd9ce6d, zh-1563bd74) — measured, released
Owner: — (released by session 01Xgpbk5jLzrCcB28yZBzYHN, 2026-10-16)
Lab `bd1` (Word 16): "none" border sides with w:space take room exactly as
ours gives them (the header style's top/bottom none sp1 add 1pt each; a
real 0.5pt line adds its width too; Word's baselines on its 0.24pt grid,
1.2/0.72 where ours are 1.0/1.0). So the style's none edges are not what
sets the rule 1pt low; the anchor's reference point is still the open
question.

### T47. zh-1563bd74 p26: how tall Word's three-paragraph footer is — partly measured
Owner: none — released by 01Xgpbk5 (2026-10-16): settled in code by 8c5c457e/e55db399 (29 pages
on Linux). On the Mac the document is 30 pages again, and that comes from the engine: b7bbf07d's
code gave 29 at 12:37 and gives 30 against the engine rebuilt after it (footer 0.4pt higher).
Asked starling-bd what that rebuild carried. Was: the Linux box's lead below,
with starling-bd's lab `hfl` (a first-line indent past the right margin: Word sets one character on
the first line; right-aligned text counts its trailing spaces)
Measured: the footer paragraph ("X" + text, first line past the margin) is two lines in
Word's footer and in ours alike (ours: X at 750.2, text 768.3; Word's text 768.8), and
the style's none edges count as in Word (lab bd1). The half point is not those; what is
left is the body case of `hfl` (one character on an overrun first line; trailing spaces
under jc=right) — being looked at.

### T48. A superscript inside a line lands after its line in the PDF (reading order)
Owner: starling-bd (Mac), from 2026-10-16 — handed back by 01Xgpbk5: the user's
go-ahead was given in starling-bd's session.
Weighed (2026-10-16): it now costs bug65649 three lines ("мм2." read as "мм."),
and fixing it means a bridge change every platform must rebuild for — held
for the user's go-ahead, not started.
bug65649 p7/13/14. Plan: expose skparagraph's TextStyle baseline shift through the
Swift bridge and draw scripts in the paragraph (engine change: rebuild every platform).

### T49. zh-15728c84 p3: "下”、“舆情" keeps the ” at its em in the body — nothing to do
Owner: — (checked by session 01Xgpbk5jLzrCcB28yZBzYHN, 2026-10-16): on the current tip the line
matches Word's print within 0.3pt ("”" 5.3pt wide before "、").
a709847b's rule covers it in cells only.

### Note from the Slides session (lenovo, 2026-10-16), relayed
PowerPoint's PDFs put 90% of text baselines on a 0.24pt (1/300in) grid
measured from the page top, apparently rounded down — the raster RichLayout's
notes give Word's prints too. Lab `bd1` shows Word's body steps 20.64/20.88
(mean 20.76) where ours step 20.8: whoever takes the page-foot rounding
question can start there.

### T53. zh-8e8d4c40 p5: lines with Noto Sans SC glyphs, and Latin in 標楷體 — Noto part DONE, Latin part open
Owner: none (was 01Xgpbk5, Mac, 2026-10-16)
On the Mac it has been 90.4% all along (98.9% was another platform); page 5
drifts 5pt low. Word's line with a Noto glyph (a compatibility ideograph
YaHei lacks) is 1.44pt lower and 0.48 deeper than YaHei's (as lab `cj2`);
ours gave it the engine's proportional leading at 1.8824 em, 2.73 lower.
And Latin in a 標楷體 run (Word: YaHei's own Latin) is set in the Liberation
Sans stand-in at YaHei's height, whose proportional ascent stands 0.9pt
over YaHei's ("據與Invoice…" 21.5 for 20.6).
Built: Noto Sans SC's line at 1.750 em, which gives Word's ascent (17.02pt
at 12pt; its 0.48 deeper is not given): zh-8e8d4c40 90.4 -> 96.6, nothing
else moved. Left: the Latin stand-in's ascent — the engine shares a run's
height by its face's own ascent and descent, so no height gives both
YaHei's ascent and its depth; a baseline shift would move the glyphs too.
Tried and reverted: the stand-in's height in YaHei runs x 0.9448 (its
ascent then YaHei's): zh-7dc3afad 98.9 -> 82.7 (a page short), zh-69bbcc3c
99.1 -> 90.2, zh-64044a1d 96.7 -> 91.2, zh-33aa9899 99.3 -> 96.9, and the
two it was for unmoved; bug57031 94.1 -> 99.7 (worth a look: what in it is
a YaHei run's Latin). Lines and paragraphs wholly in the stand-in are the
likely losers — they are YaHei's height in Word. Released.
(Mac 011uWpmC, 2026-10-16: f8adab14, pushed just before this, already
set such a line by a joiner sized from Noto's own height and baseline:
1.40pt over YaHei's line and 0.61 under it. That fix took zh-8e8d4c40
90.4 -> 98.9. On top of it, 1.750 removed the depth under the baseline:
zh-8e8d4c40 98.9 -> 98.3 and zh-64044a1d 96.7 -> 96.3. 1.8824 is
restored; both are back, and nothing else moved.)

### Leads for the Mac session (from the Windows box, 2026-10-16)
Each needs Word or is in an area the Mac has worked; claim here first.
- zh-1a3c7aa0 p32 row 111 (T32's remainder): a row that parts at the
  foot with a centred two-line date cell ("2023年1月29" / "日起禁止使用");
  Word sets "111", "2,4-滴丁酯" and "94-80-4" at 126 and the date's first
  line at 122 — the date 4pt BELOW the single lines, which no centring
  in the part we tried gives. Ours: 131, 117, 126. A lab of one such row
  at a page's foot would say how Word centres a parted centred cell.
- zh-454e2e29 p4: the diagonal header cell's labels "人數", "官等",
  "類別" are text boxes anchored in the cell, beside two `wps` line
  shapes (not drawn in ours); ours 8pt high.
- zh-799c91cd p9: an envelope of floating text boxes (stamp box "貼正 /
  郵票", address box "802高雄市…"), 20-40pt off.
  **Done by 01Xgpbk5 (Mac), 2026-10-16:** its "【附件…】" boxes on
  pages 4, 7, 11 and 13 first — anchored to the paragraph, they are
  placed from its top, space before and all, in Word (ours: from the
  text). DONE: zh-799c91cd 95.6 -> 96.8, nothing else moved; the
  boxes stand 1.5pt low now, as the page's body does. The envelope (p9):
  its address box, 308.8pt under the margin (`relativeFrom="margin"`),
  is now set there (Word 389, ours 388; it was at its paragraph, 60pt
  low) — 96.8 -> 97.2. The stamp box "貼 正 / 郵 票", in a drawing group
  under "掛號", stood 40pt low (its place not taken from the group's
  `a:chOff`) and then 3.8pt high (under the first box's top inset, not
  its own): both fixed, within 0.4pt of Word — 97.2 -> 97.6. Released.
- drawing p9-11: the banner block (nested HTML-style tables of pictures)
  stands 21pt low and 3pt taller in ours; a stray small mark at x=0.
- chartex: `c:stockChart` is drawn as a grey box (Slides' ChartPainter
  has no stock chart); the `cx` charts' fallbacks are pictures.
- Lab `ps`, mode 15: ours sets the paragraph under an inline picture and
  a trailing space 2.8pt lower than under the picture alone; Word sets
  both alike (any picture width). 
  **Done by 01Xgpbk5 (Mac), 2026-10-16:** the picture alone is right
  (zh-9c5d0c3f in mode 15: caption baseline 15.10pt under the picture,
  Word 15.07); the space's line adds its text descent (19.19). DONE: a
  single line of one inline picture and spaces measures as the picture
  alone (both labs 15.10 now). No corpus score moved.
- zh-e061a08e p1 foot: our last body line overlaps the footer by 0.2pt
  and stays (whole-pixel line boxes?); Word sends it over — the 0.24pt
  raster question.
  **Measured by 01Xgpbk5 (Mac), 2026-10-16; released.** Not the
  footer and not the print's 0.24pt raster: Word's PMingLiU line is
  1332/1024 em (1.3 of its 1024-unit em rounded up to a unit), not 1.3 —
  labs `ln` (12pt: 48 lines fit with 8..12 twips over 48 x 312) and `lb`
  (24pt: the same 8..12 over 24 x 624). The 0.2 twip a line adds 8 by
  page 1's foot (labs `ft`, `bm`: Word's threshold 8-9 twips under ours,
  with or without the footer). SimSun is the other way: lab `ls`, 48 lines
  of 12pt fit in 24 twips under 48 x 312, so about 1.297 em — not built,
  no corpus document has natural-height 12pt SimSun lines to score it.
  Built: PMingLiU at 1332/1024 em (no score moved). It cannot reach the
  page foot as it is: skparagraph rounds each line's height to a whole
  pixel (`InternalLineMetrics::height`, `::round(descent - ascent +
  leading)`; a pixel is a twip in the PDF export), so 312.19 is laid
  out as 312. Tried and reverted: counting the rounded-away fraction in
  the fit tests (sum of ascent + descent - height per line). On page 1
  it came to 4 twips, not Word's 8-9: lines with Times digits and the
  exact-height title lines round the other way (-0.5 a line), and
  `w:beforeLines` 0.12pt is laid out as 2 twips, not 2.4. Settling it
  means skparagraph keeping fractional line heights (an engine patch,
  every platform), not a Swift-side tally. Released.

### T16. Leads looked at and left (Mac, 2026-10-14)
Owner: none — notes for whoever takes them.
- `measuresShownCaps` for Word (Linux, 2026-10-17): Slides' opt-in that
  fits an all-caps run by the capitals it shows (781ec612). Turned on for
  Word's three themes and swept with and without on one base: no
  document moved (mean 91.509 either way). Left off: nothing in the
  corpus says which Word does.
- zh-6600d539 (91.8%, Linux 2026-10-16): all 16 misses are text that
  overflows its exact-height table rows (the file is a PDF conversion,
  page margins 0). Word cuts it off at the row and so do we, but Word's
  PDF keeps the hidden glyphs under the clip, and Skia's PDF device drops
  every glyph wholly outside the clip (SkPDFDevice.cpp, the
  clipStackBounds test). The line matcher keeps clipped glyphs, so it
  counts them. Not built: it would only put invisible, searchable text
  in our PDFs.
- zh-ae655121 p7, zh-e6d54ae4 (Linux, 2026-10-16): Word's PDF lacks some
  characters in its text layer (流, 金, 累 come out blank), and lines 3-4pt
  apart in neighbouring columns merge into one in the matcher. Neither
  is layout.
- zh-e061a08e: page 1 holds one line more than Word's. Its footer is a
  page number in a frame (`w:framePr`, vAnchor text, y=1) and an empty
  paragraph; our footer extent counts the empty paragraph only, and
  Word's reaches about a point higher. Which part of a framed footer
  paragraph Word counts is not known.
- zh-1563bd74 p14: our line squeezes 3.95pt to take "的" after
  "自救能力”"; the fitter counts one mark with 8pt of room. Both quotes
  are Times New Roman (7.1pt) in Word's print and in ours. Making a
  narrow-set quote give no half em did not move this line and cost
  zh-e27cd8bf 3.2 and zh-e37f8d40 1.6 — reverted; the 8pt comes from
  somewhere else.
- zh-a4b0f6ea p18: a row 3pt taller than Word's; the document has
  `w:adjustLineHeightInTable`. Turning the grid off in cells for files
  without the switch changed nothing anywhere (cells do not take the
  pitch through `_grid` as it is).
- zh-0aac9d1a (T1): Word's autofit narrows one column and widens
  another past the page; it needs the content-width algorithm.
- zh-a0e932c2 (T2): needs column regions that start mid-page.
- zh-8e8d4c40 / zh-7dc3afad (Mac, 2026-10-14): with YaHei at its
  measured 1.715-em pitch each loses one page foot (zh-8e8d4c40 now
  fits Word's sixth page's two lines on page 5). Word's lines sit on a
  0.24pt raster with the fraction accumulated; emulating that rounding
  in paging would settle these, and is the only thing that would.
- zh-799c91cd p2 "各執1份為憑。" (Mac, 2026-10-14): under `w:kinsoku` 0
  Word wraps the "。" alone though the line's six marks have 36pt to
  give, yet on the line above it squeezes to keep "公" — so kinsoku off
  does not switch compression off (tried: zh-9e08ed28 81.8 -> 67.2,
  reverted). What it changes is which piece is judged: the mark alone
  (12pt over, more than its half em) rather than "憑。" together. The
  fitter would need, for such paragraphs, to test a closing mark as its
  own piece against the half-em rule. Six documents carry the switch.
  DONE by the Windows box, 2026-10-15: zh-799c91cd 92.0 -> 97.6,
  zh-9e08ed28 85.4 -> 91.2.
- zh-6600d539 p7 (Mac, 2026-10-14): "口(網址：http://law.ndc.gov.tw/)" fills
  Word's line and the next starts with "，針對平臺" — a full-width comma
  at a line's start, with kinsoku on and the comma after a Latin word
  and ")". Our URL's widths match Word's glyph for glyph (YaHei's Latin,
  as Word draws ASCII in 標楷體 runs), but the engine will not break
  before "，", so ")，" went down with the URL. Needs a lab: a Latin word
  + ")" + "，" at a line's end, with and without a space.
- zh-f94d11c5 p3 (Mac, 2026-10-14): a justified cell line ("Normal (Web)",
  `w:wordWrap` 0) holds "權重為70" in Word and "權重為7" in ours; both
  break inside the Latin stretch "70%". Our digits are Liberation Serif
  11.3pt (narrower than Word's PMingLiU-run 7.22 steps) yet the "0" did
  not fit — the cell's width (pct table, grid 2380 twips) is the thing
  to measure first.

### Note from the Windows box (2026-10-14, for the Mac session)
The Windows sweep that first carried 2058f789 (kinsoku off) and 03f1e859
(zero-width characters in the Latin kind's style), together with e03a6891
(cell spacing — none of these documents has any), saw zh-7dc3afad 98.5%
-> 92.9% and zh-8e8d4c40 88.8 -> 87.1 of Word's lines; zh-799c91cd
82.8 -> 92.0 and zh-06c46ba9 77.0 -> 83.2 went the other way. Not split
between the two commits here.
Reply from the Mac: those two drops are 96f82ce8 (YaHei's line at 1.715
ems, not 1.72 — Word's measured mean pitch), not the kinsoku or
zero-width commits; on the Mac they were zh-7dc3afad 96.4 -> 92.0 and
zh-8e8d4c40 88.8 -> 87.1 in that commit's own sweep, each a single page
foot that Word's 0.24pt raster decides, and are explained in its
office.md entry. The gains you saw are 81b392cd + 96f82ce8 (zh-799c91cd)
and 105ee6ec (zh-06c46ba9's picture).

### Note from the Mac (2026-10-15)
Two layout fixes pushed: keep-with-next as Word's cascade (a run moves
only where a page's foot falls at a member's end with the next's first
lines not fitting; a section-ending member ends the run — zh-64044a1d
73.1 -> 87.1, 103 pages as Word's), and a table row whose first
paragraph carries a page break opens a page (the section break on the
paragraph before a table had been dropped at the row — bug65649 17.7 ->
21.9, 176 pages as Word's; lab `sectbl`). zh-6cd1befe lost a page
(59 -> 60) to the latter only because of T2: 附件3's two unequal columns
(a 1272-twip column for "附件3", the title beside it) put its title a
page down, so that document is T2's best test now, with zh-a0e932c2.

### Note from the Windows box (2026-10-15)
- The `js` space squeeze (a quarter of the spaces) has a second
  condition, f80dee36: each space gives at most half of what it would
  stretch without the word, C/n <= E/(n-1)/2 (lab `jg`, every case to
  0.1pt). It now runs for every justified paragraph from mode 15, not
  only under East Asian layout, and the fitter keeps Greek and Cyrillic
  words whole. Without the second condition `js` alone took words Word
  leaves when the word is short against the line's spare room.
- bug65649 p3 (lead, not taken): Word sets footnote 2 whole on page 4
  though its reference ("КС-3)2") is on page 3, and keeps clause 3.7
  (keepLines, 4 lines) on page 3 with that room; ours puts both
  footnotes on page 3 and carries 3.7 over. Every clause in the file
  is keepNext + keepLines, so this may be Word giving up the keep
  chain rather than a footnote rule. Needs a lab.
- Reply from the Mac (2026-10-15): the bug65649 p3 lead is taken and
  built, 7f6f7902 — Word reserves a footnote's room only when an UNKEPT
  paragraph is set; kept paragraphs' notes wait, and at the first unkept
  one those that do not fit go to the next page's foot (labs fn44/fn44k/
  fn44k2/fn44k3 in ~/starling-word-check/lab/in; Word also parts a note
  over two pages, which ours does not). Also ef56a9f1: contextual spacing
  by the named style alone, list or not. bug65649 21.9 -> 42.9 with your
  f80dee36 in between; its remaining misses are pdf-text grouping of
  "4.2.1.<tab>text" (joined in Word's print, split in ours — glyphs
  identical) and superscript marks on their own row.
- Mac, 2026-10-15, later: 44a57fd4 — a cell's text keeps clear of its
  side lines (left edge at margin + line/2, never inside the line; right
  inset margin − line/2; labs cb/cb2/cb3). Every zero-margin bordered
  table changes under it. bug65649 53.8%, zh-f94d11c5 98.5. Also
  39c92254 (a left tab shrinks to a stop nearer than the engine's 3pt
  tab) and 4c40b3e4 (break after hyphen before digit, non-EA only).
- Mac, 2026-10-15, for the Windows box: Swift 6.2.1's RELEASE optimiser
  on macOS dies ("compile command failed due to signal 6", a SIL
  verification failure in BoundsCheckOpts) inside ChartPainter._axes
  (Slides/Chart.swift) since 94f80fef; the debug build is fine. 41305b64
  marks that function `@_optimize(none)` — keep the attribute if you
  rework the function, or check a macOS release build after.
  Also 41305b64: Word's symbol faces (Symbol 1.225 em, Wingdings 1.11)
  keep their own line heights; 3096444c: a row set whole at a page's
  foot needs room for the line under it (`ruleNext`); 44a57fd4: cell
  text keeps clear of its side lines. STARLING_RICHTEXT_ROWS=<page>
  traces rows.

### Note from the Windows box (2026-10-15, later)
- 94f80fef's Chart.swift crashed the Windows toolchain's optimizer (Swift
  6.2.3: "Lexical borrows of SILBoxTypes must be of vars or captures"
  in ChartPainter._axes, exception 3). 32d4ab0d settles the two tuple
  `var`s the closures capture into `let`s; please keep such captures
  constant there.
- Sweeps here that carried 44a57fd4 (a cell's text clear of its side
  lines): zh-f94d11c5 87.7 -> 99.6, bug65649 43.3 -> 54.0, zh-e061a08e
  93.7 -> 93.0; and ef56a9f1 (contextual spacing): zh-06c46ba9 83.4 ->
  80.9, bug65649 32.9 -> 43.3.
- Mac, 2026-10-15, for the Windows box: since 223b723e (a small table
  in a cell is a table) `test/run.sh --office` dies in
  DocxTests.testNestedTableKeptVerbatim (DocxTests.swift:1344–1356):
  the kept-table ids and texts it expects are no longer what the
  importer makes, and line 1356 force-unwraps nil, so the whole office
  test step aborts (signal 5). Yours to update — the Mac sweeps' only
  known failure had been LineHeightTests.testSingleSpacingIsTheFacesNaturalHeight.
  Also: 1f705930 (space after/before share their room across a border
  too; bug59058 to Word's 52 pages), 4a380fa2 (separated-border rows),
  and a 0.75pt inset on continuation pieces (PDFKit phantom rows).
- Windows box, for the Mac: DocxTests.testNestedTableKeptVerbatim is
  rewritten for 223b723e — a small nested table is now one block
  (testSmallNestedTableIsABlock), and the flattened, kept-verbatim path
  is tested with a nested table over the 600-character bound. Both
  pass here (`swift test -c release --filter`).
- Windows box, 2026-10-15, leads left for whoever takes them:
  zh-1a3c7aa0 p51 (parted rows, the Mac's): row 127's centred cells
  ("127 二硫化碳 75-15-0") stand in the middle of the row's part on p51
  in Word's print (y 187 between 217 and 147); ours centre them over
  the whole row and the part keeps one line more. zh-1563bd74 (83.6%,
  30 pages to 29): its footer's second paragraph (style "header",
  leftChars 2280 + firstLineChars 2000, right-aligned, a near-white "X"
  then "红河县人民政府发布") is one line in Word's footer and two in
  ours; the footer then stands taller and every body page ends 35pt
  short from p26. A body lab of the same paragraph (lab `oi`) wraps in
  Word too, so the footer's case turns on something not yet found.
- Windows box, 2026-10-15, for the Mac (two of the references differ
  from Windows Word, so only the Mac's Word can lab them):
  bib-chernigovka (0%, 16 pages to 15): Windows Word prints it exactly
  as ours does — 16 pages, "МБУ «МЦБ»" at y 767, every page's lines
  matching (2026-10-15, its own print, and with the page border
  removed, made single, or at a 4pt space). The Mac's reference sets
  every page's text 18pt lower and ends each page two rows sooner. Its
  only unusual part is the art page border (`mapleMuffins`, sz 12,
  space 24, offsetFrom page) — likely how the Mac's Word places text
  under an art border. (Settled the same day by the Mac's b18da088 —
  a page background's phantom header and footer: 0 -> 91.7%.)
  zh-8e8d4c40 (87.1%, a page short): Word's Mac
  print sets 標楷體 in YaHei, and its compatibility ideographs
  (U+F900–FAFF, Big5 leftovers: 料 U+F9BE, 狀 U+F9FA, 行 U+FA08) that
  YaHei lacks in NotoSansSC-Thin — or as YaHei's empty box (零, 金, 領)
  where Noto has none; a line holding a Noto glyph is ~0.9pt taller,
  (Correction, same day: zh-8e8d4c40's page was the table grid —
  40a6bf9e took it to 98.9% — so the taller Noto lines matter less
  than this note first said.) Five more references show the Noto
  fallback (zh-06c46ba9, zh-64044a1d, zh-7dc3afad, zh-89385c94,
  zh-ae655121). Noto Sans SC is not on the Windows box; its coverage of
  U+F900–FAFF and its line on the Mac would let the layout do the same.
- Windows box: drawing.docx's "12.04.2006 - Cbonds" article heads HTML
  tables nested three deep (1 row, 394 characters). Letting a nested
  block hold blocks to three deep (tried, not kept) set it 5pt high and
  21pt left of Word's (x 34.8 to 55.7): a box's tables are placed
  without Word's outdent and cell spacing at each level.
- Mac, 2026-10-15, leads left (not built):
  - zh-2b955411 on the Mac (2026-10-16): 99.6% with bc135942 built (an
    earlier note here measured a binary that predated it).
  - zh-e061a08e p1 (Mac, 2026-10-16): not its framed footer. Labs
    ft{asis,noframe,noempty} (its package, 79 body lines) print the
    last line of page 1 at the same height in Word and ours, with or
    without the frame paragraph; the frame takes no room in either.
    The document's "（一）" line fits page 1 at y 53 in ours and goes
    over in Word, so the foot is decided within a point (the 0.24pt
    raster note above).
  - zh-64044a1d p100 (附件十四's form): in Word's print its text rows
    stand 36pt (two 18pt grid pitches) and its data rows 18.5; rows whose
    cells hold only U+3000 (hint eastAsia) are 18.5 in Word and 36.5 in
    ours, the empty ones 18.5 in both. So a line of nothing but
    ideographic spaces takes one pitch in Word. A lab of the table alone
    (u3k, u3k2) sets every row at one pitch in ours, so the page's
    context matters; not found. It costs the page's foot and page 101.
  - zh-e6d54ae4 p6: a cell merged over three rows ("依據服務特性…改善既有措施。",
    rows 19–21 of t1) brings five lines to page 6 with row 21; Word's row
    21 stands 180pt there (rule at 589.3), ours 163.9 (its flow height),
    and "施。" is drawn under our row's rule. Row 21 is set at p5's foot
    (y 661.7 of 697.3) and goes over; neither `pageHeight` (stretched
    39.8, need 163.9 on p5) nor `splitRow`'s carried sees the merged
    cell's remainder on p6. Removing `pageHeight`'s stretched guard
    alone changes nothing.
  - zh-84702a67 p3: Word's ideograph–digit automatic space is 3.1pt at
    10.5pt (0.295 em) on a line whose runs mix 10.5 and 16pt; ours 2.6,
    so the line squeezes three marks to take one ideograph Word leaves.
- Windows box, 2026-10-15, leads for whoever takes them (shapes and
  rows are the Mac's ground now): 60316 (84.8%) — its address block is
  the second text box of a drawing group (`wpg:wgp`, "Text Box 12" at
  y 4429125 EMU in the group); the reader takes only the first
  `w:txbxContent` of a drawing, so the group's other boxes are never
  read (shapes-with-text's "Where some contain text" too).
  DONE on the Mac for stacked boxes of one width, 2026-10-15 (cabe6fad):
  60316 81.8 -> 97.0. Side-by-side groups (shapes-with-text) still read
  only their first box.
  bug57031 p12 — its two-line "Note:" row (an HTML table with 15-twip
  cell spacing and margins) goes whole to page 12 in Word and parts 1+1
  in ours. (Its text at the margin: settled by 2ff0daed.) zh-2b955411
  — three cells of `w:textDirection` tbLrV/tbRlV (upright stacked
  ideographs), read as horizontal or turned. PageSpecificHeadFoot p2 —
  its footer's table floats (`w:tblpPr`, 1 twip under the paragraph
  after it) and hangs below the footer's text in Word; ours lays it in
  the flow above. zh-90e0cea8 p1 — a standard's cover of body frames
  (page- and margin-anchored), laid in the flow by ours.
- Windows box, 2026-10-15, for a decision (not built): six POI
  references are Word prints *with markup* — 58067, Tika-792, delins
  (revision balloons), comment, testComment, WordWithAttachments
  (comment balloons) — and all score near 0 because ours prints the
  page clean. The geometry is regular: the page is drawn at a scale k,
  8.3pt from the paper's left, its text column followed ~6pt later by a
  grey balloon pane ~188pt wide ending ~18pt from the paper's right
  (letter: k 0.729, pane x 407.5-594.5; A4: k 0.7367, pane 387.0-576.6),
  the page centred top to bottom; balloons "Commented [s1]: …",
  "Deleted: …", "Formatted: …" in ~6.5pt text level with their
  anchors. Whether our PDF export should print markup by default as
  Word does is a product call; done, it is worth ~4 points of POI mean.
- Windows box, leads left: zh-e27cd8bf p16 ("…10月1" | "日", mode 12,
  over 7.99 of a half em 8.3 — Word stretched the line instead; the
  automatic spaces' widths there decide it); zh-d68ac84a p17 ("…面积
  2000" | "至", a negative character grid, need 4.17 of room 33 taken
  by ours, not by Word); zh-a7728bc9 p1 (its title 5pt low).

### Note from the Windows box (2026-10-15, night)
- For the Mac: your open zh-1563bd74 squeeze ("…自救能力”" leaving "的"
  3.95 over) is settled by 9a3ea0dc. Before 2013's layout the limit is
  half of the character BEFORE the one taken (lab `lq`: after "-" 1.75,
  "." 1.46, "W" 4.95, an ideograph 5.25; an automatic space between them
  goes with the Latin side), so the 7.1pt Times quote allows 3.55. Every
  `sq15` variant falls on it. The line now breaks as Word's.
- For the Mac (parted rows, yours): zh-1a3c7aa0 p22 row 65 and p32 row
  111 part over the page foot. In Word the part on the page ends under
  the last line any cell keeps there (bottom rule drawn there) and the
  centred cells sit in that part; ours runs the part, and its rule, to
  the page's foot, so the 4-line name cell stands 3.6pt low (p22) and
  "111"/"2,4-滴丁酯" split 5pt high and 9pt low (p32). Left alone.
  Linux box, 2026-10-16: zh-15728c84 p3 is the same case, with one
  thing more — the part is never shorter than the row's own height.
  Row 9 (`trHeight` 1655 atLeast, 82.75pt; cells centred; 15pt exact
  lines) keeps five lines (75pt) on p3, and Word's part runs 407.8 to
  491.0 (83.2, the row's height and its rule), the text centred in it
  3.9pt down; ours runs to the page foot (505) with the text at the
  top, every line 5pt high. The sixth line would not have fitted
  (14pt left). Left alone (parted rows).
- Linux box, 2026-10-16, a lead that needs Word: zh-2b955411 p26's form
  rows hold 9pt text in paragraphs whose marks are 26pt (方正小标宋简体,
  `w:sz` 52), beside empty cells of the same 26pt mark. The rows are
  Word's height in ours (every rule within 0.4pt), but Word sets the
  9pt text 5pt lower in its cell than ours ("接受非国有资产的企业", "企业管理
  级次", "资质证书编号"). Whether a big mark makes the last line of a
  paragraph with text taller (its baseline lower) is the question a lab
  of one cell would answer.
- Linux box, 2026-10-16, a lead that needs Word: the letterhead rule in
  zh-e37f8d40, zh-9dd9ce6d and zh-1563bd74 (a `wps` line, wrapNone, 54.35pt
  under its header paragraph, `relativeFrom` paragraph) is 1pt low of
  Word's. The paragraph's style has `w:pBdr` sides of `w:val="none"` with
  `w:space="1"`: taken out, our rule meets Word's but the paragraph after
  it (emblem and text, which now match Word's to 0.1) goes 1pt high. So
  Word seems to keep the 1pt for the text and measure the anchor from
  above it. One cell's lab would say which: the same header with
  `w:space="0"`, and with a real top border.
- Linux box, 2026-10-16, a lead that needs Word: zh-1563bd74's p26 loss.
  The empty 28pt exact paragraph after "…提供便利。" (第六十六条) does not
  fit page 25 in ours and opens p26, so pp26-29 run a line (28-30pt) low
  and ours has 30 pages to Word's 29. In Word it fits with under a point
  to spare (its foot would be 128.15pt off the page's). Ours sets the
  footer's text 0.5-0.6 higher than Word's ("红河县人民政府发布" 73.7 to
  73.2, "- 25 -" 113.2 to 112.6). Dropping either 1pt "none" edge of the
  footer style (styleId 4) puts p26 and the page count right in ours,
  which shows only that the margin is under a point. The question: how
  tall is that three-paragraph footer in Word.
- Linux box, 2026-10-16, a lead (engine side): a justified paragraph
  that opens with ideographic spaces draws its first line an em into the
  left margin — zh-1d3d66d3, zh-04f73697, zh-5f2e209d, zh-301f097c p1,
  "　　本會依據行政院…" (Normal (Web), jc both): Word's first space is at
  the margin (42.5), ours at 30.5, the line's end where Word's is. Left
  aligned, ours is right; with "口口" for the spaces, right. Our line
  fitting counts both spaces (traced with STARLING_RICHTEXT_FIT); a word
  joiner or a box of no width ahead of them moved nothing but 0.9pt, so
  it is the engine's justification of a line holding spaces, not its
  leading-space trim. Found: skparagraph's `TextLine::justify` treats
  every whitespace cluster, U+3000 too, as a stretch — each gives up its
  width for the step, and those at a line's start get no step at all, so
  they collapse and the text after them stands at the margin. Word keeps
  U+3000 an em like an ideograph. The fix is a few lines there (count a
  U+3000 cluster as ideographic in both loops). DONE the same day as an
  engine patch (starling-engine 2ff4aa7219a,
  patches/skia-justify-ideographic-space.patch — Skia stays upstream's,
  patched by scripts/apply_engine_patches.sh after a sync): the four
  reports' first lines start at the margin; an engine built without the
  patch still sets them in it. Leading U+0020 spaces in a justified line
  still collapse (zh-e27cd8bf's "    (一)…"), left as they are.
- Also there, p19: a vMerge cell (vAlign center) whose rows part over
  pages; Word starts its first page's lines 10pt lower than ours. Not
  measured.
- 363d64e3's CR CR LF in office.md was this box's — thanks for the fix;
  edits here now keep LF in the blob.

### Note from the Linux dev box (2026-10-15)
- 363d64e3 ("a blank line between two entries") rewrote all of
  office.md with CR CR LF line endings, so every other session's edit to
  it conflicted with the whole file; 90c0be5a puts it back to LF, the
  blank line kept. Whoever made it: check the editor or `core.autocrlf`
  on that machine before the next edit.
- Linux sweeps: a bare `.build-shared` OfficeApp has no icudtl.dat
  beside it; without `STARLING_ICU` every paragraph is measured wrong
  (the fitter's boxes come back empty) and Chinese scores ~20%. With it,
  and the Noto CJK fallback (03694462), Linux at 4f7823b6: Chinese 96.7%,
  POI 81.9%, 172 of 179 with Word's page count.
- zh-1563bd74 (88% on Linux; the Windows box's footer lead): the pages
  match Word's to p25; on p26 ours starts "第十章 就业救助" 28pt low,
  because the empty 28pt-exact paragraph before it did not fit p25's
  foot — our footer is a line taller than Word's. Its second paragraph
  (`wordWrap` 0, `jc` right, leftChars 2280 + firstLineChars 2000, a
  FAFAFA "X" then "红河县人民政府发布" and five spaces) is ONE line in
  Word's print, "红" at 357.5 and the trailing spaces running to 528.6,
  7pt past the right margin: Word right-aligns it with the spaces
  counted (all but one), and its first-line indent, which leaves no room
  at all, does not push it to a second line. Ours sets "X" alone on the
  first line and the text right-aligned under it. Needs a lab in a
  footer (lab `oi` in the body wraps).
