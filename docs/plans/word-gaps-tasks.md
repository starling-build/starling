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

### T8. Load embedded fonts
Owner: —
Documents: zh-e37f8d40 (already 92.8% with the square model),
saut_page.
Known: `word/fonts/*.odttf`, obfuscated with the `w:fontKey` GUID
(XOR of the first 32 bytes). Not loaded; the name only keeps the square
face model.

### T9. Nested tables with hidden text
Owner: —
Documents: zh-454e2e29 (49%), row 2.

### T10. A section of one empty paragraph: a page or none? — DONE (2026-10-14)
Owner: session 011uWpmCQYr9neyJ1V1gzrrb
Always a page, unless a page break just before is the same break
(entry in `office.md`, lab `es`). zh-06c46ba9 0.7 -> 47.2.

### T11. zh-90e0cea8: drift on its last page
Owner: session 011uWpmCQYr9neyJ1V1gzrrb (Mac, has Word), from 2026-10-14
Documents: zh-90e0cea8 (67%, 11 pages to Word's 10).
Known: Word's last picture ends exactly at the page's usable foot, its
line's descent past it; ours now allows that (entry in `office.md`),
which took zh-6d1afa56 from 41% to 97% — note for T5's owner. This
document still needs about 1.3pt more: ours starts the picture's line
about 2pt below Word's, from drift earlier on that page. Open.

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

