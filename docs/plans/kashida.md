# Kashida line fit (Word for Windows, compat 15, Arabic-script justified paragraphs)

Target: lo-af36644e (LO set, 98.4%, 63/64 lines). The miss is the lowKashida
paragraph: Word's 3rd line holds 23 words, ours 24. Spec by amd-opus,
2026-11-06, from windows' prints of kash1 and kash2 (origin/wip/amd5-kash1-prints,
origin/wip/amd5-kash2-prints). Analysis scripts: the kash2 lab plus Python ports of
ArabicForms.width over the WindowsArabicAdvances.arial table.

## What the prints say

1. **kash1 tells us nothing about low.** kash1.docx has no settings.xml, so it
   is legacy compat (< 15); there Word's low lines equal its both lines. Our
   squeeze path is off in legacy anyway. Keep amd-5's medium/high reserve (a57732f40).
2. **The widths are right.** Text width is 451.3 pt (A4, 9026 twips). Our
   per-word widths match Word's Arial advances. The engine's fit trace gives
   the same overflow as the Python model to 0.01 pt: line 2 is 1.76 pt over,
   line 3 is 1.98 pt over at full width.
3. **Word's `both` is our existing half-stretch test, exactly.** A line may
   squeeze in its last word if each space gives up no more than half of what
   each space would stretch if the word went to the next line:
   `need/g <= 0.5 * stretch/(g-1)`. Here g is the number of spaces and stretch
   is the width minus the line without the word. On kash2 the fitted share is
   0.498-0.499, so it is 0.5.
4. **Our engine measures that stretch from the wrong place (bug, both and low).**
   The fit loop places an Arabic word in pieces, splitting it after letters that
   don't join forward (ا د ذ ر ز و). So when the last piece fails, `x` is in the
   middle of the word. `stretch = width - (x - wordSpaces.last.w)` then leaves
   out the word's earlier pieces. Example: "طولانی" has pieces "طولا" and "نی";
   the trace shows stretch measured from "نی" (8.4 pt) instead of from the word
   start (27.6 pt). That is why our `both` lines break early: we drop the word
   at width cut 1.5-2.0 pt, Word only at 7.5 pt. For a Latin word that is one
   piece, the two measures are the same.
5. **`lowKashida` is the same test, but joined letters count as stretch
   points.** Each joining letter pair on the line, before the word being
   tried, counts as w = 3.1 extra spaces in the stretch share:

       need/g <= 0.5 * stretch / (g - 1 + 3.1 * joins)

   This reads as: low justification stretches spaces and kashida, so a long
   joined line has more places to stretch and gives each space less reason to
   shrink. The feasible band is w in [2.96, 3.24]; 3.1 is its middle.
   Simpler forms all fail:
   - a flat share with no joins term is infeasible: it needs c ≥ 0.061 and
     c < 0.041;
   - so are a constant overflow, a per-space, a per-join or a per-letter
     allowance, and a tatweel-width allowance (each misses by 0.1-0.6 pt).

   The deciding line is line 1, which holds the 50-yeh word (84 joins). Word
   refuses it 1.18 pt over, yet takes line 2 at 1.76 pt over.

## Predicted breaks (words per line; tw = end indent in pt, W = 451.3 - tw)

lowKashida, rule above: **33/33 widths, 132/132 lines** (ours today: 23/33).

| tw | Word | rule |
|---|---|---|
| 0.0 (the document) | 15/23/23/5 | 15/23/23/5 |
| 0.5-1.0 | 15/22/23/6 | 15/22/23/6 |
| 1.5-16.0 | 14/22/22/8 | 14/22/22/8 |

both, existing 0.5 test with the stretch fix: **32/33 widths, 129/132 lines**
(ours today: 16/33).

| tw | Word | rule |
|---|---|---|
| 0.0-7.0 | 15/23/24/4 | 15/23/24/4 |
| 7.5-8.0 | 15/23/23/5 | 15/23/23/5 |
| 8.5-9.5 | 15/22/23/6 | 15/22/23/6 |
| 10.0 | 14/22/22/8 | 15/22/23/6 MISS (one 0.5 pt step late, line 1) |
| 10.5-16.0 | 14/22/22/8 | 14/22/22/8 |

Kash2 has 66 widths in all. Ours matches 39 of them today; the rule matches 65.
Honest scope: only about 6 lines across the widths actually decide the rule;
the rest fit naturally.

## Functions to change (amd-5)

All in `_fitEastAsianLines`, apps/OfficeApp/Sources/OfficeText/RichLayout+EastAsian.swift
(the Windows space squeeze, near `let stretch =` / `let halfStretch =`, ~line 1905):

1. **The stretch base.** Measure the stretch from the start of the word being
   tried, not from `x`:
   `stretch = width - (x at the start of the word's last space)`.
   The simplest way is to record x when a space is appended to `wordSpaces`
   (the appends near lines 2118 and 2123) and use the last one's x. For
   one-piece words this changes nothing. Gate it to Arabic-script
   right-to-left paragraphs (`p.style.rightToLeft && _squeezesRightToLeft`) if
   land.sh shows Latin or CJK movers.
2. **The low share.** When `p.style.eastAsian["w:jc"] == "lowKashida"` and the
   paragraph is right-to-left (same gate as above), add `3.1 * joins` to the
   `wordSpaces.count - 1` denominator of `halfStretch`. Count `joins` over the
   line's units from the line start up to the last space:
   - a pair of adjacent letters counts when the first joins forward and the
     second joins back (ArabicForms' joining table);
   - lam-alef counts as one join with the letter before it, none inside it.

   Add `ArabicForms.joins(_ units:)` next to `ArabicForms.width`, walking the
   units the same way width does.
3. Leave roomSpaces (0.25 of each space), the medium/high `fitReserve` in
   RichLayout+Paragraph.swift (~1505), legacy mode and Latin paragraphs as
   they are. Word's Latin low (lab kashida, Calibri) refuses a squeeze that
   both takes, and no joins form explains that. It is not in this document's
   misses, so it stays open.

Check before landing: kash2 (66 widths) should read 65/66. lo-af36644e should
read 64/64. Use `STARLING_FIT_LOG=1`: the FITS row for a=353 at tw 0 should
show half=0 for low and half=1 for both.

## If a second lab is wanted

Counting **letters** instead of joins fits as well: w in [1.6, 2.02] scores 33/33,
and the doc still comes out right. To separate the two, use one lab: the kash2
paragraph, low only, end indent 0-6 pt in 0.25 pt steps, in two copies. In copy
A, the words on line 3 are replaced by words of equal width made of
non-joining letters (د ذ ر ز و ا: many letters, few joins). In copy B, they are
replaced by fully joined words (ب س م ی: many joins). The two rules predict the line-3 break at
different indents in A and B; run both copies through the Python model first
to pick word sets where the predictions sit at least 1 pt apart.
