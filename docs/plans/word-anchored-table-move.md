# Where Word lands a page-anchored table it moves to the next page

Planner spec, amd-opus, 2026-11-14. No code changes. The owner of the code is
lenovo-5 (the "tablemove" rule). Target doc: xd f42177d2 (12 pages against
Word's 11). The page-9 table lands at 64.9 in ours and 51.8 in Word, and the
overflow pushes one extra page.

## Short version

- **Already landed** (lenovo-5, f24dab9de + 080e32b96, RichLayout+Paginate.swift,
  rule trace `page-anchored-table-whole-goes-to-the-next-page-where-the-text-before-it-reaches-its-place`):
  a page-anchored table whose place the text before it reaches into goes whole
  to the next page, and the text stays. On the new page we set it at its
  `tblpY` (the `newPage()` branch just after that trace, `let target = ts0?.pageOffsetY ...`).
- **Word does not always keep `tblpY` there.** Over 21 Word prints, the landing
  is `min(tblpY, C)`, where C depends on the line-grid pitch and the top margin.
  C does NOT depend on `tblpY` (60, 67, 70 and 80 all land at 51.84 at pitch 18) or on the
  title size (24.5, 25, 25.5 and 26 pt all land at 51.84).
- **No formula fits the prints we have.** They all reuse one complex 8-row
  table from f42177d2, so nothing separates "the table's rows decide C" from
  "the page and grid alone decide C". Lab **atmove** (12 docs, below) separates
  them.
- **atmove read (2026-11-14; see "atmove results" and "IMPLEMENTATION ORDER").**
  1. Word moves the table ONLY when it cannot fit whole below its place. Text
     reaching into the place is not enough. A table that fits stays at `tblpY`,
     and the text wraps beside it. We move those today: 4 of the 5 short
     variants, wrongly.
  2. Rows of exact height land at `tblpY`. Other rows land at C (51.84 at
     pitch 18), with or without row 1 (52.32 without). The anchor paragraph
     changes nothing. C still has no model. Leave the landing at `tblpY`.

## Measurements (Word for Windows, compat 15; landscape A4 595.3 high, bottom margin 14.2)

Table top on the new page (top rule y, pt). The page-1 title is 26 pt with ruby
and wraps to a second line at 18 pt. Tables are tblpY 60 unless noted. Sources:
lenovo-5's lab/fltpage5, fltpage6, fltpage7, fltpage8 (`word-win/`).

| pitch | top margin | tblpY | lands at | row 1 height | first cell baseline |
|---|---|---|---|---|---|
| none | 21.3 | 60 | **44.28** | 18.02 | 57.12 |
| 12 | 21.3 | 60 | **58.32** | 24.5 | 74.42 |
| 14 | 21.3 | 60 | **41.40** | 28.58 | 59.66 |
| 15 | 21.3 | 60 | 60.02 | 30.48 | 79.10 |
| 15 | 30 | 60 | 60.02 | 30.48 | 79.10 |
| 16 | 21.3 | 60 | **50.76** | 32.54 | 71.06 |
| 18 | 21.3 | 50 | 49.92 | 18.5 | 63.02 |
| 18 | 21.3 | 60, 64.85, 67, 70, 80 | **51.84** | 18.5 | 64.94 |
| 18 | 30 | 60 | **51.84** | 18.5 | 64.94 |
| 18 | 40 | 60 | 60.02 | 18.48 | 73.10 |
| 20 | 21.3 | 60 | 60.02 | 20.4 | 74.18 |
| 22 | 21.3 | 60 | **48.36** | 22.46 | 63.50 |
| 24 | 21.3 | 60 | **58.32** | 24.5 | 74.42 |
| 30 | 21.3 | 60 | 60.02 | 30.48 | 79.10 |
| 36 | 21.3 | 60 | 60.02 | 36.48 | 82.10 |

Other facts from the same prints:
- The table is taller than a page, so it always continues on the page after,
  starting at the top margin (21.36 or 30.0 or 39.96).
- Row 2 is 126.51 at every pitch. Rows 3-7 grow with the grid (6 lines at pitch
  18-36, 12 lines at 12-16). Row 1 takes one grid line at pitch 18 and above,
  and two at 12-16.
- Moving the table up does not let more of it fit on the page. At pitch 18 with
  top 40 (lands at 60.02) the page holds the same rows 1-5 as with top 21.3
  (lands at 51.84).
- Pitch 12 and pitch 24 print identically (C 58.32, same baselines). Whatever
  decides C sees 2 lines of 12 as 1 line of 24.

Rejected models (each misses at least two rows of the table above by 2 pt or more):
top margin + N·pitch; the nearest grid line at or before `tblpY` (lenovo-5:
57.3 / 35.3 / 53.3 / 57.3 / 43.3 for 12 / 14 / 16 / 18 / 22); an offset of
`tblpY` minus the text's reach on page 1 (C ignores `tblpY`); a move up to fit more
rows (see above); row 1's text baseline on the page grid (the remainder against
the grid changes with the top margin); and the top margin + the anchor
paragraph's grid height + a constant.

## Lab atmove (built; out of git)

/data/s/amd-opus/starling/lab/atmove: 12 docx plus mk.py. Base:
fltpage7 r7-p18-ty1600 (f42177d2's own package), with tblpY set to 1200 (60 pt),
top margin 21.3, pitch 18 unless named. Each variant changes one thing.

| doc | change | what it decides |
|---|---|---|
| m01-ctrl | none | the control: must land at 51.84 |
| m02-rows12 | rows 1-2 only (fits the new page whole) | is C there only when the table has to part? |
| m03-rows1to5 | rows 1-5 (fits whole at 60, ends 530.6) | the same, with a table nearly a page tall |
| m04-rows1to6 | rows 1-6 (just too tall at 60) | does C follow the table's height? |
| m05-norow1 | without the 18.5 pt first row | does C follow row 1? (ours keeps this table on page 1: the move rule needs text past row 1, and row 1 is now 126.5) |
| m06-exact | every row hRule exact at its pitch-18 height | does the rows' grid growth matter? |
| m07-anchor20 | the paragraph after the table is 20 pt (2 grid lines) | does the anchor paragraph's height decide C? |
| m08-anchortext | the paragraph after the table holds "あ" | the same, with text |
| m09-twoafter | two empty paragraphs after the table | does the text after the anchor count? |
| m10-p24-rows12 | rows 1-2, pitch 24 | C against pitch for a short table |
| m11-p12-rows12 | rows 1-2, pitch 12 | the same (ours keeps it on page 1) |
| m12-nogrid-rows12 | rows 1-2, no docGrid | the same, with no grid |

Ours (tip 2963038e1) lands every moved one at 60 (`tblpY`). To read the
prints, take the first horizontal rule on page 2 and compare it with 60.02:
/data/s/amd-opus/fltrules.py `<word-win>/*-orig.pdf` prints every page's rules.

What to conclude:
- If m02, m03 and m10-m12 land at 60 while m01 and m04 land low, C comes from
  the table parting. Then compare C with the part that fits on the page.
- If all of them land low, C belongs to the page. m07-m09 then say whether
  the anchor paragraph sets it.
- m05 and m06 isolate row 1 and the grid growth.

## atmove results (Word for Windows, compat 15, 2026-11-14)

Prints: lab/atmove/word-win/ (windows' readings are in WINDOWS-NOTES.txt).
Columns: table top / table bottom on the page it is on.

| doc | Word | ours, tip 2963038e1 |
|---|---|---|
| m02-rows12 | **stays p1**, 60.02-205.49 | moved to p2 at 60.5 |
| m03-rows1to5 | **stays p1**, 60.02-531.10 | moved to p2 |
| m10-p24-rows12 | **stays p1**, 60.02-211.49 | moved to p2 |
| m11-p12-rows12 | **stays p1**, 60.02-211.49 | stays p1 |
| m12-nogrid-rows12 | **stays p1**, 60.02-205.01 | moved to p2 |
| m01-ctrl | p2 at **51.84** (rows 1-5), p3 at 21.36 | p2 at 60.5 |
| m04-rows1to6 | p2 at 51.84 | p2 at 60.5 |
| m05-norow1 | p2 at **52.32** | **stays p1** (our rule needs text past row 1, which is 126.5 here) |
| m06-exact | p2 at **60.02** (= `tblpY`), same rows on p2 | p2 at 60.5 |
| m07-anchor20, m08-anchortext, m09-twoafter | p2 at 51.84 | p2 at 60.5 |

What the prints settle:
1. **The move condition is that the table does not fit whole below its place.**
   m03 (ends at 531.1 from 60) stays, and m04 (would end near 639) moves. Each
   has the same title reaching 33 pt past the place. Where a table that stays
   meets the text, Word wraps the title's second line to the right of the
   table at its own baseline: m02 line 2 sits at x 553.8, baseline 81.86, with
   the table spanning x 36-546. Not decided: whether "fits" is measured to the
   bottom margin (581.1) or the page edge (595.3). No variant ends between the two.
2. **The landing.** Exact rows land at `tblpY` (m06). Rows with an at-least
   height land at C whatever the table holds: rows 1-5 and rows 1-6 give the
   same 51.84, and no row 1 gives 52.32. The anchor paragraph doesn't affect
   it (m07-m09: its size, its text, a second paragraph).
   C is therefore a property of the page and grid, applied only when the rows
   can grow. It is not grid phase: top margins 21.3 and 30 give the same C.
   It is not set by row heights or by `tblpY`. No formula over the 13
   pitch/margin points above fits, so do NOT hard-code a value per pitch.

## IMPLEMENTATION ORDER (for lenovo-5)

All of it is in RichLayout+Paginate.swift, in the move test just above
`RuleTrace.hit("page-anchored-table-whole-goes-to-the-next-page-where-the-text-before-it-reaches-its-place")`.
Find it with `grep -n 'whole-goes-to-the-next-page' apps/OfficeApp/Sources/OfficeText/RichLayout+Paginate.swift`.

1. **Move only a table that does not fit whole below its place.** `whole` (the
   bottom of the table's last row, computed just above the test) is already
   there. Add `target + (whole - c.rowTop) > contentH + 0.01` to the `if`. Keep
   `target + c.ownRowHeight + line <= contentH + 0.01`.
2. **Then try dropping the first-row conditions.** Replace `under > c.ownRowHeight + 0.01`
   and `reach > c.ownRowHeight + 0.01` with `reach > 0.01`. Word moves m05,
   whose text reaches only 33 pt past the place, under its 126.5 pt first row.
   Re-check the four docs those conditions protect: zh-3ab8a2fb, lo-6a5857f2,
   lo-0dd5bc0a and dx2 9baed400. If all four keep their place (they should,
   when their tables fit whole below the place), keep the simpler test. If any
   one moves, put the two conditions back, AND-ed with step 1, and note m05 as
   a known miss.
3. **Render lab/atmove** (12 docx in amd-opus's checkout,
   /data/s/amd-opus/starling/lab/atmove), with the full pair env, each into a fresh
   folder. Read the first horizontal rule of each page with
   /data/s/amd-opus/fltrules.py.
   - m02, m03, m10, m11 and m12: 1 page, table at 60.5 (ours prints rules 0.48
     below Word's).
   - m01 and m04-m09: table on p2 (m05 too, if step 2 stuck).
4. **Look at m02's page 1.** Word sets the title's second line beside the
   table, at x 553.8 and baseline 81.86. If ours puts it under the table,
   leave that alone: it is a separate wrapping gap, so note it on the board.
   Do not fix it in this change.
5. **Leave the landing alone.** The `newPage()` branch keeps `target`
   (`tblpY`). That is right for exact rows (m06). For at-least rows Word lands
   at C, which has no model yet. f42177d2's page-9 table (64.9 against Word's
   51.84) and its extra page stay open. Do not write a per-pitch table of C.
6. **Movers.** Today's rule moves any table whose place the text reaches into.
   The new test keeps every table that fits whole. List the docs where the
   trace fires today (`OFFICE_RULE_TRACE=<file>`, on every set) and A/B those.
   Each table that stops moving should come back to Word's page. Submit with
   `DOCS=` set to those doc ids, plus f42177d2 (which must not change: its
   table is 724 pt tall at pitch 18 and still moves).

## Code to change, once C is known (later)

One place: the `newPage()` branch right after the trace
`page-anchored-table-whole-goes-to-the-next-page-where-the-text-before-it-reaches-its-place`
in RichLayout+Paginate.swift. `target` there is `pageOffsetY` less the page
inset. Make it `min(target, C)` under `RichTextTheme.wordWindowsPages` and the
same move condition, and leave the move rule itself alone.

## Expected movers

f42177d2 (xd) should go up: one page fewer, and the page-9 table 13 pt higher.
The move rule fires on few documents. Before submitting, list them with the
rule trace (`OFFICE_RULE_TRACE=<file>`, every set) and A/B those documents. Score
only those; the landing changes nothing else.

## Traps

- Measure the table top by its top rule, not by cell text. Cell baselines
  move with row 1's grid height.
- Our rules print 0.48 pt lower than Word's (60.5 against 60.02 at the same
  place), from the line's width. Compare like with like.
- docx-app-render.sh reuses an old output folder: render with --convert into
  a fresh folder.
