# Word flat-pie best-fit labels: the lo-f9b9a8fc label-5 jump (amd-opus, 2026-11-06)

## Round 2 (after pielabel5 and pielabel6): verdict

**Neither candidate reproduces Word, and nothing should be built for label 5.** Both the iterative
overlap pass and the ordered "first position that does not overlap" search collapse, on these
prints, to the one fixed layout our code already draws. Three findings rule them out (below).
What Word does is a joint layout of all labels that we cannot recover from label positions alone.
Recommendation: release label 5 as unexplained; lo-f9b9a8fc stays 87.5. One unrelated, cheap y fix is
offered at the end (bottom labels 3.5 pt lower), to be checked on a real render first.

Data: 104 prints, 754 outside labels: pielabel3 (`wip/lab-pielabels-prints`), pieang, piewid,
pielabel5, pielabel6 (each `wip/lab-<name>-prints`). piesize3/4 were read but not scored (wrapped
two-line labels, other columns, no leader data). Script: `test/lab/pie-spec/p7.py LABDIR`
(LABDIR/<name>/test/lab/... from `git archive origin/wip/lab-<name>-prints test/lab`); its output,
one row per print, is `test/lab/pie-spec/PREDICT.tsv`.

### What pielabel5/6 add

1. **Positions are whole pixels.** Every label's height from the pie centre is a whole number of
   pixels at 96 dpi (0.75 pt steps: -57.76, -26.28, -21.76, +52.50, +61.50 ...). Across, labels carry
   the pie centre's sub-pixel phase, so the same layout repeats every 3 pt (4 px) of frame width
   with 0.5 pt of jitter.
2. **The full 8-label chart has three layouts in 350-370 pt**, keyed by the frame width rounded to
   pixels: A up to 479 px (label 5 at -26.8, +61.5), B 480-488 px (label 5 at -54.4, +52.5 with a
   leader; this is lo-f9b9a8fc at 360 pt), C from 489 px (label 5 at -40.5, +58.5; labels 1, 2, 3, 4
   and 7 move 3-9 pt as well). Label 7 changes earlier, between 359 and 359.25 pt, where the
   pie centre crosses half a pixel. pw-w300 and pw-w400 are two more layouts.
3. **Labels never come close to each other.** In all 104 prints the nearest two label boxes are at
   least 7.3 pt apart, and the gaps do not bunch at any value.

### Why both candidates fail

- **No contact signature.** An overlap pass, or a search that skips blocked positions, leaves each
  moved label touching what blocked it, at the padding distance. Word's prints show no such
  contacts. The largest box padding at which Word's own layouts stay overlap-free is about
  3.5 pt across and 1.25 pt up and down. At any padding in that range, the default layout (today's
  rule) of the 8-slice chart has no overlap. So both candidates move nothing and predict one fixed
  layout at every width.
- **Labels attract.** Label 5 alone stands at (-49, +59). With label 4 present (p45) it stands at
  (-39, +59), and label 4 at (+35.5, +60): the two move about 10 pt *toward* each other. Neither
  candidate ever moves a label toward another.
- **Width matters with nothing near an edge.** Between 479 and 480 px the nearest label is 79 pt
  from the frame's side, yet label 5 moves 27 pt. Taking away label 2 (upper right) moves label 5
  (lower left) 12 pt, with nothing touching in between. A test against neighbours or the frame
  cannot see either.

What fits all of this is a global optimiser over all the labels at once, whose objective changes
smoothly with the frame's shape, with the result snapped to pixels. The jumps would then be switches
between local optima. The irregular narrow frames (242 and 246 differ from 240 and 244) are what
such an optimiser does once the frame edge binds. The objective cannot be read back from label
centres, and guessing one would fit these 8-slice labs and nothing else.

### Prediction table (best candidate = today's fixed layout)

Both candidates reduce to today's rule, so their predictions are today's. Counts are labels
within 3 pt of Word, with the label rule placed on **Word's own pie** (centre and R from the print).
The per-print rows are in PREDICT.tsv.

| lab | prints | outside labels | x and y within 3 pt | y within 3 pt |
|---|---|---|---|---|
| pielabel3 | 14 | 102 | 33 | 67 |
| pieang | 7 | 56 | 31 | 46 |
| piewid | 7 | 48 | 21 | 31 |
| pielabel5 | 29 | 202 | 39 | 135 |
| pielabel6 | 47 | 346 | 84 | 193 |
| **all** | **104** | **754** | **208 (28%)** | **472 (63%)** |

What fails: label 5 in every B print (label 5 is fixed at one place, so all of A, B and C cannot be
right at once), the narrow frames 240-260 (labels pushed into the pie and the frame), and the
moved labels in C. For scale, the best possible *fixed* rule (one best offset per radius and angle,
fitted to these prints) gets 78% (x and y) and 92% (y). It would hit lo-f9b9a8fc's label 5 only by
choosing B over A, and B wins there only because the labs crowd around 360 pt. That is fitting one
print, so it is not recommended.

### Chart.swift

- **Label 5:** no change. `_pieLabels`, the `tuneFlat` branch, stays as it is.
- **Optional y fix (separate task, low priority):** labels below the pie stand 3-4 pt lower in Word
  than our rule puts them, on Word's own pie (median +4.3 at 157.5 deg, +2.7 at 202.5, +3.1 and
  +3.9 at R 60). Round 1's fact 2 saw the same thing (about 2.5 pt more gap below). In `_pieLabels`,
  `tuneFlat` branch: `gapY = tuneFlat ? (dy > 0 ? 7 : 3.5) * k : gap`. Offline that takes y hits from
  472 to 589 of 754 (63% to 78%). **Check it on a real render first:** our pie on lo-f9b9a8fc is
  0.74 pt bigger and sits differently from Word's, and label 4 there already matches. The y fix may
  break it. Land only if the pair run shows lo-f9b9a8fc and the 756 set flat or up.

---

# Round 1 (superseded where round 2 disagrees)


Planner's spec, from amd-1's Windows prints only (nothing built): pielabel3
(`wip/lab-pielabels-prints`, PIEEQ-WORD.tsv), pieang (`wip/lab-pieang-prints`),
piewid (`wip/lab-piewid-prints`), plus Word's own print of the document
(`test/corpus/docx/lo/word-win/lo-f9b9a8fc47c97aa6-orig.pdf`). 190 outside labels in 30 prints.
Scripts: test/lab/pie-spec/ (load.py; a2 = touch point per label, a5 = docs side by side, a6 = the 4/5 pair; run beside a lab/ folder holding the three prints branches' test/lab/<name> dirs). Polar frame: angles clockwise from 12 o'clock, y down.

## Verdict

**No rule can be written from these prints, and none should be landed.** The jump is a
decision Word makes in its own label search. The thing that triggers it is not in any
geometry we measured. One cheap lab separates the two explanations left (below).
lo-f9b9a8fc stays at 87.5 until that lab is printed.

## What the prints prove

1. **Every outside label is pinned to the rim inside its own slice.** The text box's
   nearest point lies 0-5 pt outside the circle (median 1.6) in 189 of 190 labels.
   The point where it touches the rim stays inside the slice's own arc: at most 19.4 deg
   off the middle angle, against a half-span of 22.5. Only the touch point's position
   along the arc varies. So "lean" is a slide along the rim, never a gap.
2. **Where nothing is moved, the pinning is a fixed table by angle** (pieang, R about 55):
   - within about 13 deg of 12 or 6 o'clock, the box is centred on the rim point;
   - from about 17 to 57 deg off upright, the box's inner corner sits on the rim point;
   - from about 62 to 103 deg, the middle of its inner side sits there;
   - from about 107 to 153, the inner corner again, with about 2.5 pt more gap below the pie.
   Every label of the 8-equal-slice pie (22.5 + 45k) sits on or near a band edge. That is
   why those labels, and only those, are sensitive.
3. **Word marks a moved label with a leader line.** In Word's print of lo-f9b9a8fc only
   label 5 has one. It runs from the rim point at exactly 202.5 deg (230.3, 220.5) at 45 deg
   to (225.8, 225.0), then flat to the label box's right edge (221.8). So label 5 is a
   *moved* label, placed beside its rim point like a callout. Labels 1-4 and 6-8 sit at
   the pinned position.
4. **The trigger is not anything near the label.** pw-w350 and pl3-base (frame 350 vs
   360 pt) have the same pie (R 53.76, same centre y) and the same neighbours to 0.5 pt:
   label 4 (38.5, 60.75) both, label 6 dy 22.5 both, legend 12.9 pt below both. Yet label 5
   is (-26.8, 61.5) in one and (-54.4, 52.5) in the other. So no test against neighbour
   labels, the legend, the title or the pie can flip it.
   It is not pixel rounding either: w300 and base put the pie at the same pixel phase
   (centre at 200 and 240 px from the frame's left), yet they differ.
5. **The order Word places labels in matters.** pl3-ang45 is base turned by one slice
   (same angles, same R, same frame), but the 202.5 label there is index 4, not 5. Word puts
   it at (-45.4, 59.2), not (-54.4, 52.5). In every print the labels that move are the ones
   just clockwise past 12 or 6 o'clock (22.5 and 202.5). Their neighbour across the axis
   (157.5, 337.5) never moves: base, w300, w350 and w400 all have label 4 at x 37.2-38.7
   and label 8 at -40.3 to -40.9. That fits a placement in slice order, where a label is
   tested against the label placed before it (label 1's "before" being label 8).
6. **Only base jumps upward.** Label 5's height against label 4's, in all 17 prints with
   both outside: base -8.2 pt; the other 16 lie between -1.5 and +2.3. So a rule fitted to
   reproduce base is fitted to one case.

## Why the obvious rules fail (checked offline)

- **Collision with label 4 (with padded boxes):** the base pair is 29.9 pt apart, and so
  is the w350 pair. A threshold that moves one moves both.
- **Leaning toward the nearest axis, as a smooth function of angle:** that gives one
  answer for base and w350. They differ by 27 pt.
- **Label boxes wider than the text, touching at the axis:** the half-gap of the top pair
  is 41.6-42.0 in four prints, but 34.1 (w300) and 37.5 (w400) in two, with the same R.
- **Box scaled to the frame width, or a search step that scales with it:** four widths
  cannot test this, and w450-w600 (R 60.49) do not move at all.

## What to change in Chart.swift

Nothing for label 5 yet. `_pieLabels`, the `tuneFlat` branch (bestFit outside, Word
document; the `halfW` / `down` lines) stays as it is. Fact 2's band table is a candidate
to replace the `min(1, |dx|/0.5)` ramp, but only together with the lab below, and gated on
the 17+30 prints. It does not move lo-f9b9a8fc's score.

Predicted positions: every pinned label stays as today. For lo-f9b9a8fc label 5 there is
no honest prediction. The target is Word's text box x 172.8-220.3, y 218.9-227.9 (centre
-54.4, +52.5 from the pie). Ours is 186-233, 223.9-234.9.

## The one lab that separates the two rules left (pielabel5, Windows)

Rule A: Word tests a label against its neighbours (fact 5).
Rule B: Word tests it against the frame or plot box, through a step tied to the frame
size (fact 4).

Start from pl3-base:

1. **Label 5 alone** (`c:dLbl idx=k` with `c:delete val=1` for every other k), at w350 and
   w360. Then **labels 4 and 5 only**, at w350 and w360. That is 4 documents.
   - Label 5 alone still jumps between w350 and w360: rule B.
   - Label 5 alone sits as label 4's mirror, and the 4+5 pair jumps: rule A, label 4 is
     the input.
   - Neither jumps: rule A with a third label as the input. Add "all but 6" and "all but 1".
2. **Frame width 350-370 in 1 pt steps** on base (21 documents). Look for one threshold or
   a period. A period ties rule B to the frame's units. A single flip gives the threshold.
3. In every print, record **which labels have a leader line** (Word's own "moved" flag).
   Record it in the existing pielabel3, pieang and piewid PDFs too, if Windows still has
   them. That is a column in meas.py: grey 2-segment strokes starting on the rim.

With (1)-(3), the rule is: which test, against what, and the step. amd-1 implements it in
`_pieLabels` as a placement pass in slice order after the pinned position, applied only
to labels the test moves. Moved labels get the callout position from fact 3: label beside
the rim point, leader 45 deg then flat.
