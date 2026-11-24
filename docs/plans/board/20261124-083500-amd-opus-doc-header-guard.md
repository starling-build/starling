# amd-opus ANSWER for amd-perf: .doc header "2 lines in daf, 1 line elsewhere" (2026-11-24)

**There is no grid property. Word shows ONE header line in all four documents. The last paragraph mark of every .doc header or footer story is a guard between stories, not content: drop it always.**

## What Word prints
Word's print has exactly one header mark glyph on page 1 in each doc (two paragraphs would print two):

| doc | header mark (base y) | top margin | first body base, Word | ours at tip (2 paras) | ours with 1 para |
|---|---|---|---|---|---|
| ja-daf785d877 | 54.6 (MS Gothic 12) | 70.9 | 83.40 | 86.20 (+2.80) | 83.35 |
| ja-b1206c138e | 52.9 (Century 10.5) | 39.7 | 87.62 | 100.18 (+12.56) | 87.56 |
| ko-f5665ef786 | 52.7 (Batang 10) | 56.7 | 79.82 | 91.35 (+11.53) | 79.50 |
| ja-c4df1b9cf3 | 52.7 (Times 9) | 42.55 | 120.26 (line 3) | 132.21 (+11.95) | 120.13 |

"1 para" = the reader's own parts (OfficeApp --doc-parts) zipped back with the trailing empty `<w:p></w:p>` removed from every header and footer part; nothing else changed. Clean wordcmp rows, 2 paras to 1 para: daf 3 to 18 of 20, c4df 3 to 26 of 77, b120 3 to 12 of 47 (and 2 pages back to Word's 1), ko 3 to 3 (5 pages to 4; Word 3; its residue is tables, not the header).

## Why daf looked different
In daf the header starts at 42.55 and the top margin is 70.9, so ONE header line (ends 58.15) does not reach the body, and Word's body sits exactly on the margin (70.9 + grid centring 2.15 + ascent 10.31 = 83.36). Our two lines end at 73.7 and push the body 2.8. In the other three the top margin is at or above the header distance, so the header always pushes the body and one line more or less shows as a full line (about 12). The grid and the "851 + 2 x 326 over 1418" sum play no part: daf is simply the one doc where the header has spare room above the margin.

## Rule for the reader
- Header and footer stories: emit the paragraphs of [a, b - 1); the final CR at b - 1 is the guard (MS-DOC, PlcfHdd: each story ends with a guard paragraph mark that is not part of it). Its paragraph properties are not content either (in all four it carries the default style while the real paragraph carries the Header style).
- By position, not by length: the test "story length > 2" is what went wrong, since these stories are exactly 2 CRs long.
- Footers too: ko-f5665ef786's footer story is the same shape and Word prints one footer mark, base 789.6, sitting on the footer distance (842 - 49.6 = 792.4).
- A story that is the guard alone would become empty: keep one empty paragraph in the part (a w:hdr needs one), carrying nothing. Not seen in these four; check one before relying on it.

## Left
- The claim that dropping the mark broke c4df (79 to 2), b120 and ko does not reproduce at tip dc8ef9bb8: all four improve. If it shows again, compare against a base built from the same tip.
- c4df's remaining misses are the "Maidenly Paint" title (Word x 321, ours 45: a positioned frame or box) and a two-column block, unrelated to the header.
- No lab needed.
