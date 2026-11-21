# Real section columns in the Word layout (plan, amd-opus, 2026-11-21)

Job 16 (starling-bd). Starting point: amd-4's finding on sa1 f39b852f
(board 20261121-010935-amd-4): a multi-column section is laid out as a
one-row TABLE, so a page foot splits a table row where Word flows columns.

## 1. What exists today (three regimes)

Columns are already modelled as VIRTUAL PAGES: `_pages[k]` is one column,
physical page `k / _columns`, column `k % _columns`. `_pg_newPage`
(RichLayout+Paginate+Pages.swift:148) moves to the next column, and past the
last one to the next page. A column break is `pageBreakBefore + columnBreak`
on the paragraph, so it takes the same path. Left edges come from
`_pxColumnLeft` (RichLayout+Layout.swift:3042, uses `PageSetup.columnOffset`,
so unequal `w:col` widths and spaces are placed right).

| regime | when | where decided |
|---|---|---|
| A whole-document | every section has the same count | `_columns` (Layout.swift:3034) |
| B per-section (`_perSection`) | sections disagree on their counts | Layout.swift:3312-3335, "columns step 2", ca1aa7376 |
| C one-row table (`TableStyle.sectionColumns`) | a multi-column section with NO table in it that starts continuous, or is followed by a continuous section, or is the file's last continuous section | importer, Docx.swift:3480-3600 (e898cbbe6, 2026-10-23, older than B) |

Regime C wins over B: `tableMakesColumns` (Layout.swift:3319) counts such
a section as ONE column, so the file usually ends up in regime A with one
column. That is f39b852f: `_oneColumn` true, `_perSection` false.

Already in B: balancing at a continuous section end (post-pass,
RichLayout+Paginate.swift:771-935, redistributes the placed pieces over
`nb` columns), sections stacked under a balanced block on the same page (the
`head` pieces, tdf139336), unequal widths (wrap at the widest column, then
`_specInsetBoxes` holds narrower columns' pieces in by re-wrap, Layout.swift:
760 and 3107), floats wrapping in other columns (Layout.swift ~700-770), RTL
columns, a continuous section's own side margin, `leavesColumnsUnbalanced`.

Missing everywhere: `w:sep` (no separator line is drawn at all); footnotes
in columns under B (`slotNotes` is A-only, Paginate.swift:123).

## 2. Reach (eval sets, scanned 2026-11-21)

Docs with any section `w:cols num>1`, and how many take regime C. "Unmatched"
is the C docs' Word lines not matched in the current base scores (not all of
it is caused by columns).

| set | docs | with columns | regime C | C docs' Word lines | unmatched | C docs under 90% |
|---|---|---|---|---|---|---|
| 756 | 775 | 7 | 6 | 3358 | ~11 | - |
| lo | 608 | 31 | 17 | 376 | ~0 | - |
| xa | 109 | 5 | 2 | 1121 | ~11 | - |
| xb | 188 | 18 | 18 | 4252 | ~286 | docx-bff1c672 61 |
| xd | 119 | 2 | 2 | 2178 | ~110 | - |
| xs | 130 | 3 | 3 | 299 | ~6 | - |
| dx2 | 1807 | 41 | 33 | 6059 | ~1258 | 17 docs, lowest 2f95cc62 9, f2c764d0 13, 09bfb084 34, 99cfc555 35 |
| sa1 | 159 | 10 | 8 | 1363 | ~244 | 978697fd 38, e6e4bf30 54, f39b852f 85 |
| sa2 | 128 | 7 | 6 | 440 | ~31 | 78bf1be7 68, 5cf365e6 84 |
| all | 4023 | 124 | 95 | 19446 | ~1960 | 23 |

Features inside the column sections (124 docs): unequal widths 40, column
breaks 43, tables 21, floats 23, `w:sep` 5, footnotes 3.
Script: test/tools/cols-reach.py (lists regime-C ids per set; it approximates the importer's condition, so after P1 use the RuleTrace hit as the exact list).

## 3. Target design

One rule: **a section with `num>1` is set in its own columns, by the
paginator, never by the importer.** Regime C goes away; its docs fall into
A (all sections agree) or B.

1. Entry. Docx.swift:3480-3600: do not build the row. Paragraphs stay body
   paragraphs with their `sectionXML`/`sectionPage`; a `w:br type=column`
   stays `columnBreak + pageBreakBefore` on the next paragraph.
   Layout.swift `tableMakesColumns` and the three `sectionColumns` checks
   (3319-3384), SplitRow.swift:333 and Paginate.swift:3070 go when C is gone.
2. Flow. Column to column and page to page is `_pg_newPage` over the
   virtual pages, unchanged. Under B a section of fewer columns than the
   most skips the unused slots (Pages.swift:202). f39b852f p5 is the test:
   Word sets heading ¶157 in columns 3-5 of p5, the rest on p6.
3. Widths and spaces. Equal: `columnWidth` from `w:space`. Unequal:
   `columnSpec` (B keeps it; A clears it at Layout.swift:3372, so A with
   unequal sections must keep it too). Lines wrap at the widest column and
   `_specInsetBoxes` holds the narrower ones in. Word wraps each column at
   its own width; the inset gives the same breaks only if the inset is the
   exact width difference. Check per glyph against Word's print, no
   tolerance.
4. Column breaks. Next column; from the last column, next page. Port the
   importer's special cases as paginator rules, each with its doc:
   zh-6cd1befe (a paragraph holding only the break opens the next column
   with its empty line), zh-b8de3ae2 (a break into the second column before
   a section on its own page is not a page), zh-8f9b19f4 (a final continuous
   three-column section is one line, not a page each), e898cbbe6 (a
   column's last space after may stand past the foot).
5. Balancing at a continuous section end. Keep the post-pass, with Word's
   facts from sa1 978697fd (amd-perf #487, real section columns: `num=3`,
   continuous sectPr on the last list item; Word sets the three one-line
   items 1+1+1 at x 90/258/426, same y):
   - the even length EXCLUDES the space after the block's last paragraph
     (8 pt there: counted, the target is 484 not 431 and the split 2+1);
   - same-style list items use contextual spacing, so only the last keeps
     its space after;
   - balance only the ending section's own lines on this page: the old
     piece list also held paragraphs from another page. Filter `seq` by
     `_sectionOf == _sectionOf[pgs.i - 1]` and by physical page.
   #487's `lastAfter` (5 lines, old path) carries over. No balancing at a
   page-breaking section end, at the file's last section, or with
   `w:noColumnBalance`. Open (lab L1): does a section that holds manual
   column breaks still balance (f39b852f's sections end continuous and are
   split by breaks), and is Word's length the least height that fits
   (search) or our greedy total/N cut?
6. Separator (`w:sep`). Draw a line in the middle of each gap, per page,
   from the section's top on that page to its lowest column bottom. Line
   width, colour and how far it runs (balanced block vs full column; a gap
   with an empty column): lab L2. Paint only; no line moves.
7. Tables in columns: column width, rows part at a column's foot into the
   next column (virtual page). Already true in A/B; 21 docs to check.
   Floats: `horizontalFrom=column` from `_pxColumnLeft`; margin floats
   across columns keep the existing wrap pass. f39b852f's text-box column
   (¶160...) is the test: Word keeps it whole on p6.
8. Footnotes. Extend `slotNotes` to B when every section on the page has
   the same count >1; otherwise page-wide as now. 3 docs; only with a doc
   that shows it.

## 4. Steps (each one a small PR)

- P1 (no change by default). A switch, OFFICE_SECTION_COLUMNS=flow
  (read once into a RichTextTheme static), that skips the importer's row.
  RuleTrace hit `section-columns-as-row` on the old path. Lands
  byte-identical everywhere (switch off).
- P1 check, and the check for every later step: with the switch ON, every
  doc with no `num>1` section and the 29 column docs outside C must render
  byte-identical to the switch OFF (compare LayoutDump output or page
  PDFs over all nine sets); only the 95 C docs may move.
- P2. Switch on, regime C docs: column breaks and the four importer special
  cases as paginator rules (item 4). Measure the 95 per set.
- P3. Balancing (item 5): own-section filter; lab L1 if the 95 still show
  balance misses.
- P4. Unequal widths under A (keep `columnSpec`), per-glyph check on one
  doc with unequal columns (dx2 has 18).
- P5. Flip the default when, switch on, each set's mean is not lower and
  every doc that drops is explained, fixed, or approved by starling-bd by
  full id. Ask amd-8 to add a switch-on sweep of the 95 to the round from
  P2 on, so the rounds see it before the flip.
- P6. Delete regime C (importer block, `tableMakesColumns`, the
  `sectionColumns` style field and checks, SplitRow.swift:333).
- P7. `w:sep` painting (lab L2). P8. Footnotes in B columns, if a doc
  needs it.

Labs (at most 2 rounds each): L1 balancing with manual column breaks and
least-height vs greedy (2-3 columns, unequal widths, keepNext items); L2
`w:sep` line metrics. Build the docx by hand, check each XML part with a
namespace-aware parser.
