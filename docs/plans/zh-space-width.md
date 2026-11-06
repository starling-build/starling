# Width of spaces in zh documents (planner spec, amd-opus, 2026-11-06)

Question (starling-bd): lenovo-2's census found a two-space run's width in
Word's prints "constant per document" (zh-a78d52e7 7.45, zh-eec0747a 4.02,
zh-0060058e 8.1, most 8.04). Which per-document property sets it?

## Answer

**There is no per-document space width.** `w:balanceSingleByteDoubleByteWidth`
is the only per-document switch, and the code already reads it
(`RichDocument.balancesSpaceWidth`). The census measured the whole gap
between the two neighbours. That gap also holds the line's letter-spacing
and justification stretch, and it cannot tell U+0020 from U+00A0 or U+3000:
the PDF text layer writes all three as " ". Once each space's own advance
is measured (origin to origin, less the line's per-character stretch), the
"constants" break down into four things the code already models, plus one
rounding effect.

Under the flag, for a space in a Latin face between ideographs:

1. **U+0020 is half the run's em.** 16 pt gives 8.04 (see 5).
2. **Less twice the run's `w:spacing`**, the same doubling the ideographs
   get. zh-a78d52e7 (-4 tw) 7.68, zh-5dc5ce34 and zh-6cd1befe (-6 tw) 7.44.
   The census's 7.45 / 7.16 / 7.29 are this plus the neighbour's own
   spacing inside the gap.
3. **U+00A0 alone keeps its face's own width** (Times 0.25 em, Calibri
   0.226). A no-break space then a plain one gives [own, half]. A plain one
   then a no-break one gives [half, half]. This is the existing lab `nb`
   rule in `RichLayout+Span.swift` (`close()`, around lines 300-358).
   zh-eec0747a's 4.02 is this: 37 of its pairs are "  ". Its 3
   "  " pairs print at half an em, and only those. The same goes
   for zh-903376c0, zh-f2cf109b, zh-9dd9ce6d, zh-17749c13, zh-d0bfd38c,
   zh-e9f256c1 and zh-01bbcd4d.
4. **Font size**: zh-e74dd0a1 is 15 pt, so 7.56 is its half em.
5. **Word's widths come in 1/600-inch steps (0.12 pt).** An em is
   round(size x 600/72) steps: 16 pt is 133 = 15.96, 15 pt is 125. The
   balanced space is round(em/2), with halves rounded up: 67 = 8.04 at
   16 pt, 63 = 7.56 at 15 pt. The doubled spacing is round(2 x spacing x
   600/72) steps: -4 tw gives -3 steps, so the space is 64 = 7.68 and the
   ideograph 130 = 15.6; -6 tw gives -5 steps, so 62 = 7.44 and 128 =
   15.36. Every number above matches the print to 0.01 pt. The layout
   quantises nothing like this today (the only 0.12 grid is small caps,
   `RichLayout+Span.swift:382`).

zh-0060058e (8.1 / 9.08) and zh-8e6ce2ed (9.07) are 8.04 plus the
justified line's stretch.

zh-6c447317 is the one real narrowing: 0.42-0.43 em, but only on full
justified lines. That is a line squeeze, already landed as a9f72b916, not a
width property.

## Hit rate

Measured: every two-space run between two ideographs, in a Latin-drawn
face, in the 92 flag documents with such runs. That is 1355 runs; each
space is measured on its own, with the line's stretch taken out.

- 1120 print as [half, half]. All of these are U+0020 pairs, or a plain
  space followed by U+00A0.
- 136 print as [own, own]. All 136 are in the 8 documents that hold
  "  " pairs, and no document has more of them than it has such
  pairs.
- 8 print as [own, half], all U+00A0 then U+0020 (zh-b875d786 5,
  zh-cb56e605 3).

**1264 / 1355 = 93% follow rules 1-4 exactly.** The other 91:

- 36 sit on stretched or squeezed lines, where this method cannot pull the
  space's share of the stretch apart from its width. zh-6c447317's 6 are
  among them (a9f72b916).
- About 9 are [own, half] with two plain spaces. The first space sits in a
  heading run whose ascii face is 黑体 and prints in Arial, 0.278 em:
  zh-c9f4d690, zh-6043ad90, zh-5313b71d, zh-15428325, zh-57e33dec.
- 6 are full-em pairs (zh-76700e5f, zh-90e0cea8, zh-9db183d5,
  zh-cd8987db).
- About 40 are on short lines with only a few ideographs, where the
  stretch estimate is poor. zh-5dc5ce34's 4 are really rule 2 (0.466 em =
  -6 tw doubled). The rest are scattered: zh-55270438, zh-621d8756,
  zh-e68a2f57, zh-6e7ff836, zh-d68ac84a, zh-7654804a, zh-8415d258.

## Predicted width per census document (per space, origin to origin)

| doc | what it is | predicted | Word |
|---|---|---|---|
| most (16 pt, no spacing) | rule 1 | 8.04 | 8.04 |
| zh-a78d52e7 | -4 tw | 7.68 | 7.68 (7.80 on stretched lines) |
| zh-5dc5ce34 | -6 tw (style) | 7.44 | 7.44 |
| zh-6cd1befe | -6 tw | 7.44 | 7.44 |
| zh-e74dd0a1 | 15 pt | 7.56 | 7.56 |
| zh-eec0747a | U+00A0 pairs | 3.96-4.08 (Times, steps) | 3.96 / 4.08 |
| zh-0060058e | rule 1 + stretch | 8.04 + stretch | 8.07-8.1 |
| zh-6c447317 | squeeze (a9f72b916) | 8.04 plain lines | 8.04 plain, 6.74-6.85 full justified |

## For lenovo-2: what to change

1. **No per-document width, and no new face or fontTable gate.** altName,
   panose, charset, sig, hint, theme fonts and missing faces are not what
   separates the classes. The two classes that looked like a "face" effect
   are U+00A0 (rule 3) and the doubled spacing (rule 2), and both are in
   the code already.
2. **zh-a78d52e7 p8 ("第二十三条  奖励经费…纳入预算") is not a space-width
   bug.** Word's line, measured in its print:
   - 第二十三 at 15.6 each, 条 at 15.51, the spaces at 7.68 and 7.80, the
     rest at 15.6;
   - the line starts at 110.66 (margin 79.4 + firstLine 31.2);
   - 预 ends at 516.05, against a right edge of 515.9 (A4, margins 1588 tw).

   So Word lets 预 in **0.1-0.15 pt past the measure**. In exact points
   (16 pt em, 7.6 spaces) the line is 405.2 pt against 405.3 available, so
   it should fit. If ours wraps, our advances on that line are wider than
   this. First step: print our per-character advances on that line and
   compare them with the numbers above. Then decide between rule 5 (1/600-
   inch steps) and a fit tolerance. Do not narrow the spaces to make it fit.
3. **Rule 5, only after the trace.** Quantise the balanced space in
   `RichLayout+Span.swift` around lines 1567-1576 (the `fraction` /
   `extra += em * wScale * fraction - _spaceWidth(s) + …` line): use
   round(em/2) steps less round(2 x spacing) steps instead of em/2 less
   2 x spacing. This widens each space by +0.04 at 16 pt, +0.08 at -4 tw and
   +0.06 at 15 pt. Do it only together with the ideographs' 15.96 em (133
   steps) if our layout does not already set that. A wider space with an
   unquantised 16.0 em would move the whole corpus. Gate it with a pair
   (756 + LO) like any width change.
4. Residual, not in scope: a first space in a 黑体-ascii heading run printing
   as Arial's own 0.278 em (the 5 documents above).

Data and scripts (Word prints only): `~/tmp/ss/zsw/`.
- `cen3.py`: the census with each space's own advance; output `runs3.tsv`.
- `fit.py`: class per space; output `fit.tsv` (doc, page, class, a1, a2,
  own width, line stretch, …).
- `cp.py`: code points per document; output `cp.txt`.
- `ext.py`: fontTable, settings and resolved fonts per document; output
  `xml.json`.
