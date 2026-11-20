# Word table autofit in no-compat documents (Pandoc percentage tables)

Planner spec, amd-opus, 2026-11-13. It covers no code changes. It was written for
xb jpn-z21601833-463426 (55.5, best 75.5), lenovo-5's handoff on the board.

## Short version

- The sharing logic we already have is right. One measure is wrong: the
  "kept-whole" width of a cell (`whole`, from `_minContent(..., contentFit: true)`).
- Word measures a cell's kept-whole width by breaking ONLY at spaces (and tabs,
  line breaks) and AFTER an em dash (U+2014). Nothing else breaks it: not
  ideographs, not Japanese punctuation (、。（）〜), not Latin or math pairs
  (`/`, `(`, `)`, `²`, `∂`, `−`, `＝`, `_`, `.`).
- Our code still lets Latin and math pairs break (they fall through to the
  ordinary line-break rules). That cut t12's math cell from 1078.7 pt to about
  500, so column 3 came out 323 pt where Word has 382.5.
- With that fixed, plus a 0.25 pt content for an empty cell, one model fits all
  14 lab tables (37 columns) within 0.25 pt.
- The two "contradictions" in the handoff were not contradictions:
  1. t12 does not need "all-whole". It needs the Latin and math pairs glued.
  2. t15 does not need "split". It needs the one break after the em dash
     ("引力—|—閉じ込め").
  Glue everything except after an em dash, and both fit.

## Status (2026-11-14): landed; atcol9 read; one optional line left

- **The change in this spec has already landed**: 023ad2439 (lenovo-5,
  2026-11-13): the em-dash break, the glue, and the 0.25 pt for an empty cell.
  xb 463426 went from 55.5 to 99.4, and round 437 found no doc down. On today's
  tip (2963038e1), t12 comes out 15.4 / 80.9 / 382.5, the same as Word's print.
- **Regime 3 has also landed**: ec0c6f11f (2026-11-13) keeps each column's
  kept-whole width as its minimum and fills from there toward `max`.
- **atcol9 (Word prints, compat 12) against today's tip.** Widths are columns
  1 / 2 in pt; "rule" is the reading the print confirms.

| table | Word | tip 2963038e1 | rule |
|---|---|---|---|
| a, em dash | 209.7 / 269.1 | 209.6 / 269.2 | breaks just AFTER the em dash (before: 214.0; glued: 190.1) |
| b, hyphen U+002D | 241.4 / 237.4 | 241.4 / 237.4 | breaks after the hyphen |
| c, en dash U+2013 | 240.4 / 238.4 | 240.4 / 238.4 | breaks after the en dash |
| d, slash | 214.6 / 264.2 | 214.7 / 264.1 | glued |
| e, U+2010 | 215.5 / 263.3 | **241.2 / 237.6** | **glued**: Word does NOT break after U+2010 |
| f, regime 3 | 217.7 / 261.1 | 217.6 / 261.2 | width = *m* + `whole` + (`max` − `whole`) · *k*, *k* = (*R* − Σ`whole`) / (Σ`max` − Σ`whole`) (by max: 173.2; by whole: 391.8) |

  Corpus check of the regime-3 rule: xb jpn-z21601833-c2301a, table 14:
  Word's column 1 is 239.0 and the tip gives 238.9.
- **Only table e is still wrong**, and it moves no corpus document. Nine docs
  across the sets contain U+2010. The one with no compat mode
  (xb docx-5dc87fc7) has no table, so the gate never fires on any of them.

## IMPLEMENTATION ORDER (for the implementer; one optional step)

There is nothing left to build for xb 463426. The one remaining step is a
correctness fix with no expected movers; land it only if the coordinator wants it.

1. Open `apps/OfficeApp/Sources/OfficeText/RichLayout+Layout.swift` and find
   the contentFit glue branch: `grep -n 'a == 0x2014 { parts = true }'`. The
   `else if` right after it lists the characters that still fall through:
   `!(a == 0x2D || a == 0x2010 || a == 0x2013)`.
2. Remove `a == 0x2010` from that list, so it reads `!(a == 0x2D || a == 0x2013)`.
   In the comment above, replace "hyphen or en dash (unmeasured ...)" with:
   "lab atcol9: it parts after a hyphen U+002D or en dash U+2013, never after
   U+2010 or a slash".
3. Build. Render `lab/atcol9/e-u2010.docx` from amd-opus's checkout
   (/data/s/amd-opus/starling/lab/atcol9) with the full pair env plus
   `STARLING_RICHTEXT_AUTOFIT=1`. The trace must print
   `content fit [215.5, 263.3]`, within 0.2. Then render a-d and f: each must
   still match the table above within 0.2.
4. Check t12 (lenovo-5's lab/atcol5/t12.docx) still gives 15.4 / 80.9 / 382.5.
5. Submit with `DOCS=-`. Expected movers: none, in any set.

## The model (no compat mode, Word for Windows, pct-width table, contentFit)

Write *m* for the cell's left plus right margins (10.8 pt here). The room *T* is
the column width plus the margins: 478.8 for 100% of 468. Write *R* = *T* − *n*·*m*.
For each column:

- `max` = the widest paragraph in the column set on one line, trailing spaces
  dropped.
- `whole` = the widest piece in the column, where a piece runs between
  break points, and the only break points are spaces, tabs, line breaks, and
  just after U+2014.
- An empty column has `max` = `whole` = 0.25 pt (5 twips). This is measured
  from 6 empty columns in 5 prints, ±0.1. Without it the worst error is 0.95 pt.
  PROVISIONAL: the cause is unknown.

Then, by regime:

1. Sum of `max` ≤ *R* (under-full): stretch. Width = (`max` + *m*) · *T* /
   Σ(`max` + *m*). That is today's `stretch` path.
2. Sum of `max` > *R* and sum of `whole` > *R*: width = *m* + `whole` · *R* /
   Σ`whole`. That is today's `high = low` branch.
3. Sum of `whole` ≤ *R* < sum of `max`: width = *m* + `whole` + (`max` −
   `whole`) · *k*, with *k* = (*R* − Σ`whole`) / (Σ`max` − Σ`whole`). Measured
   by atcol9 f; landed in ec0c6f11f.

Regimes 1 and 2 are exactly the code at RichLayout+Layout.swift
`_autofit`, from about line 1505 ("No compat mode, lab atcol4"). Only the
inputs change.

## Measurements: every lab table

Word's column widths come from where the text starts in each print. Column
edge = text start − 5.4, and the table runs from 66.6 to 545.4. Contents are
Word's own glyph advances from the print, spaces included, margins not. "tip"
is the current office binary (/data/s/amd-8/bins/278393777, trace
STARLING_RICHTEXT_AUTOFIT=1, Windows settings).

| lab | regime | max per column | whole per column | Word | model | tip |
|---|---|---|---|---|---|---|
| t12 | whole | 13.3 / 229.8 / 1078.7 | 13.3 / 204.0 / 1078.7 | 15.4 / 80.9 / 382.5 | 15.4 / 81.1 / 382.4 | 19.0 / **136.5** / **323.3** |
| t12-c12 | whole | e / 229.8 / 1078.7 | e / 204.0 / 1078.7 | 10.9 / 81.6 / 386.3 | 10.9 / 81.8 / 386.1 | 10.8 / **138.9** / **329.1** |
| t12-c1only | stretch | e / 229.8 / e | e / 204.0 / e | 20.3 / 438.4 / 20.1 | 20.1 / 438.5 / 20.1 | 19.7 / 439.4 / 19.7 |
| t12-c1-nodigits | stretch | e / 229.8 / e | e / 204.0 / e | 20.3 / 438.4 / 20.1 | 20.1 / 438.5 / 20.1 | (not run) |
| t12-no3 | stretch | 13.3 / 229.8 / e | 13.3 / 204.0 / e | 41.9 / 417.8 / 19.1 | 41.8 / 417.8 / 19.2 | 41.8 / 418.3 / 18.7 |
| t29 | whole | 48.0 / 384.0 / 235.0 | 48.0 / 384.0 / 204.6 | 44.5 / 280.2 / 154.1 | 44.5 / 280.1 / 154.3 | 44.6 / 280.0 / 154.2 |
| t29-c12 | whole | e / 384.0 / 235.0 | e / 384.0 / 204.6 | 11.1 / 301.8 / 165.9 | 11.0 / 301.9 / 165.9 | 10.8 / 302.0 / 166.0 |
| t29-c1only | stretch | e / 384.0 / e | e / 384.0 / e | 12.7 / 453.5 / 12.6 | 12.7 / 453.4 / 12.7 | 12.4 / 454.0 / 12.4 |
| t29-no3 | stretch | 48.0 / 384.0 / e | 48.0 / 384.0 / e | 60.7 / 406.8 / 11.3 | 60.6 / 406.8 / 11.4 | 60.8 / 406.9 / 11.1 |
| t15 | whole | 48.0 / 943.7 | 48.0 / **588.0** | 45.4 / 433.4 | 45.3 / 433.5 | 45.4 / 433.4 |
| t15-1run | whole | 48.0 / 943.7 | 48.0 / 588.0 | 45.5 / 433.3 | 45.3 / 433.5 | (not run) |
| t15-nopunct | whole | 48.0 / 835.7 | 48.0 / 835.7 | 35.8 / 443.0 | 35.6 / 443.2 | 35.7 / 443.1 |
| t15-kanji | whole | 48.0 / 1116.0 | 48.0 / 1116.0 | 29.8 / 449.0 | 29.7 / 449.1 | 29.7 / 449.1 |
| t15-short | stretch | 48.0 / 339.9 | 48.0 / 289.5 | 69.0 / 409.8 | 68.8 / 410.0 | 68.9 / 409.9 |

Here e = 0.25. The model's worst error is 0.25 pt. Today's code fails only the
two tables whose widest whole piece holds Latin or math pairs (t12, t12-c12),
by up to 59 pt. Its empty columns run up to 0.6 pt narrow because it has no
0.25 pt content.

How the break points were decided (whole width of t15's long cell):

| break points | t15 col2 whole | worst error over all 14 |
|---|---|---|
| spaces only (lenovo-5's "all-whole") | 943.7 | 12.6 pt (t15 col1 33.0 vs 45.4) |
| spaces + before an em dash | 576.0 | 0.57 pt |
| **spaces + after an em dash** | **588.0** | **0.25 pt** |
| today's code (Latin pairs break) | 588.0 for t15, but t12's math cell about 500 | 59 pt |

Other observations:

- t12 column 1 is 15.4 wide: 4.6 pt inside, narrower than one digit (6.65). So
  Word sets no minimum in regime 2. "12" prints one digit per line, and the
  share follows `whole`, not what fits.
- t15 against t15-nopunct: the only break in t15's long cell is the em dash.
  Removing the punctuation removes it, and col1 falls from 45.4 to 35.8.
- No break at 、 or 。 (t15 and t12 col3), at （ ）, at 〜 followed by a digit
  (t15), or at `/` (t12's "(1/c²)∂²τ/∂t²", which keeps 1078.7 whole).
- The lenovo-5 claim that "empties shrink to margin plus one glyph" is wrong. The space
  Word writes for an empty cell (2.64) is its paragraph mark. An empty cell's
  content is about 0.25, not a glyph.
- Faces in the prints: MS Mincho for kana, kanji and full-width marks; Cambria
  for Latin, digits and the em dash; Cambria Math for ∂ ∇ ℏ. Our t15, t29 and
  under-full numbers already match Word, so our advances agree in these faces.

## Code change

Everything is in apps/OfficeApp/Sources/OfficeText/RichLayout+Layout.swift.

1. **`_minContent`**, the contentFit branch at about line 1752:

   ```swift
   else if theme.wordRules, RichTextTheme.wordWindowsPages, document.compatibilityMode == nil,
           p.cell != nil, pctWidthTable, contentFit, a >= 0x2E80 || b >= 0x2E80 { parts = false }
   ```

   Replace the `a >= 0x2E80 || b >= 0x2E80` condition. Under the same gate
   (`gate` below):
   - `gate, a == 0x2014` → `parts = true` (measured: t15).
   - `gate, a is not a hyphen or en dash (U+002D, U+2010, U+2013), and neither
     a nor b is Thai, Lao, Khmer or Myanmar (U+0E00-0EFF, U+1780-17FF,
     U+1000-109F)` → `parts = false`.
   - Otherwise fall through to the existing chain, unchanged. Hyphens and en
     dashes are unmeasured, so keep today's behaviour for them; atcol9
     decides them. Thai keeps its dictionary breaks, as the old comment says.

   Spaces, tabs, no-break spaces and line breaks are handled by the branches
   above this one, so they are untouched. Update the comment there (it says
   "Latin and Thai text keeps its own breaks"): cite atcol5-8 and this file.

2. **`_autofit`**, the per-cell loop at about line 1452: for an empty paragraph
   (`p.text.isEmpty`, no image), when `document.compatibilityMode == nil`,
   `pctTable` and `RichTextTheme.wordWindowsPages`, add `_px(0.25)` to
   `wWhole` and `widest`, but not to `w`. Comment that it is PROVISIONAL and
   measured on t12-c1only, t29-c1only, t29-no3, t12-c12 and t29-c12.

3. No other change. The `stretch` path and the `high = low` share stay as they
   are. Regime 3 is untouched.

Keep both inside `_minContent` / `_autofit` as they are now. They are not
layout-frame functions, so the stack note does not apply. Don't add big local
value types anyway.

Verify before landing:

- Render the 14 lab docx with STARLING_RICHTEXT_AUTOFIT=1. Each "content fit"
  line must be within 1 pt of the Word column in the table above. Tools:
  /data/s/amd-opus/atcol-fit/cells.py (Word widths and per-cell advances from a
  print) and model.py (the model over all 14; run with ~/venv-word/bin/python).
- 463426: for every table where the trace changes (lenovo-5 found t5, t6, t7,
  t10, t12 and t13 differ between today and all-whole), compare the content
  fit with Word's column starts in
  /data/corpus-cache/staging/xb/word-win/jpn-z21601833-463426-orig.pdf. Map
  trace tables to Word pages by cell text, not by index.

## Expected movers

Census: /data/s/amd-opus/atcol-fit/census.py. It looks for files with no
compatibilityMode, a pct-width table with an equal grid and no tcW, and a
non-space Latin break pair inside a piece over about 40 pt, in a table near
over-full.

| set | no-compat docs | candidates |
|---|---|---|
| 756 | 132 | 0 |
| lo | 94 | 0 |
| xa | 18 | 0 |
| xb | 15 | **4**: jpn-z21601833-463426, -acd729, -4e6465, -c2301a (all one author's Pandoc files) |
| xd | 12 | 0 |
| xs | 17 | 0 |
| dx2 (whole, including the Latin sample) | 249 | 0 |

- **Up:** 463426. Today t12 is 19.0 / 136.5 / 323.3 against Word's 15.4 / 80.9 /
  382.5. Its row heights are probably the page-22 drift of about 100 pt
  (untested). Target: back towards 75.5.
- **Must hold:** acd729 at 61.5 or more (t15 and t29 are unchanged by the
  model; its other 19 candidate tables may move), 4e6465 at 92.3 and c2301a at
  93.5. The board figures are from 2026-11-11, so re-measure them on the tip
  first.
- **Everything else:** identical. The change sits in OfficeText, so land.sh also
  runs the Latin sample. Do the usual 4-language dx2 A/B (ko, ja, hi, bn); the
  census expects no movement there.

## atcol9: the follow-up lab (printed 2026-11-14; results under Status above)

No lab is needed for the first landing. This one would decide the three gaps
the change leaves alone. It is one docx built from atcol5's t12.docx package,
so it keeps Pandoc's settings.xml (no compatibilityMode) and styles. Each table
is pct 5000 with an equal grid and no tcW, and the tables are separated by
empty paragraphs. Column 1 of every table is a reference cell of 20 kanji
(whole = max = 240 pt), so column 1's width reads column 2's measure directly:
column 1 content = 240 · 457.2 / (240 + X).

| table | column 2 text (no spaces unless shown) | prediction if Word breaks there | if glued |
|---|---|---|---|
| a | 25 kanji + "—" + 5 kanji | after the dash: X 312, col1 198.8 (before the dash: X 300, col1 203.2) | X 372, col1 179.3 |
| b | "x"·40 + "-" + "y"·10 (Cambria) | X ≈ 240, col1 ≈ 229 | X ≈ 299, col1 ≈ 204 |
| c | as b with "–" (U+2013) | same as b | same as b |
| d | as b with "/" | same as b | same as b |
| e | as b with "‐" (U+2010) | same as b | same as b |
| f, regime 3 | col1: 3 words of 10 kanji, space-separated (whole 120, max ≈ 365); col2: 25 words of 2 kanji (whole 24, max ≈ 663) | share by max (today): col1 content 162; CSS-style min + (max − min)·k: 207; share by whole: 381 | |

Render it with our engine before sending it to Word, and check that each pair
of predictions is more than 3 pt apart in our own render (atcol labs have come
back unreadable before).

## Traps seen on this task

- Without borders, column edges come only from text starts. In this Pandoc
  style, edge = text start − 5.4 pt (the 108-twip margin), and the table starts
  5.4 pt left of the margin.
- Word writes a space glyph (2.64 pt) for every cell's paragraph mark, so a
  line's right end from pymupdf runs one space long. Sum glyph advances
  instead.
- The lab prints are Letter with 1-inch margins (no sectPr), so 100% = 468 +
  10.8 = 478.8.
