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

## Open tasks

Ranked roughly by lines at stake. "Known" is what has been measured;
start from there.

### T1. Autofit tables
Owner: —
Documents: zh-0aac9d1a (63%), and likely others among the forms.
Known: `w:tblLayout autofit`, grid 1350/3022/1526/2680 twips; Word draws
the columns 34.5/187.7/110.4/156.5pt, wider than `tblW` and the text
column. Word's autofit algorithm (content minimum and maximum widths)
needs labs; nothing built.

### T2. Per-section column layouts
Owner: —
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

### T8. Load embedded fonts
Owner: —
Documents: zh-e37f8d40 (already 92.8% with the square model),
saut_page.
Known: `word/fonts/*.odttf`, obfuscated with the `w:fontKey` GUID
(XOR of the first 32 bytes). Not loaded; the name only keeps the square
face model.

### T9. Nested tables with hidden text
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box), from 2026-10-15
Documents: zh-454e2e29 (49%), row 2.

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

### T12. Squeezing marks to fit a character: the limit on a character grid
Owner: none. Documents: zh-d68ac84a (80%, first parting page 10).
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

### T17. zh-9c5d0c3f: road-sign table rows
Owner: session 011ZXp8eXomzYegGkuu7484P (Windows box), from 2026-10-14
Documents: zh-9c5d0c3f (54%).
Note from the Mac (2026-10-14): 49beaff9 (dashes and ellipses in East
Asian runs set in the CJK face) moved zh-9c5d0c3f 55.9% -> 66.7% on the
Mac — found through T11, not taken from this task; what is left of it
is yours.

### T16. Leads looked at and left (Mac, 2026-10-14)
Owner: none — notes for whoever takes them.
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
