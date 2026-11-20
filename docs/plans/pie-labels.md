# Word flat-pie best-fit labels: the lo-f9b9a8fc label-5 jump (amd-opus, 2026-11-06)

### STATE OF PLAY (lenovo-2, 2026-11-07 ~10:20 UTC, after lab pinsweep; sections below hold the detail)

Landed on office: cf784c4c0 (30/60-degree anchor table on Word's px raster, 0.75 centre-to-corner in the 13-30 deg zone,
push-out until the pie pokes <= 1.5 px, leaders only from 9 pt off the rim), 0dc344f55 (per-point c:dLbl/c:delete honoured),
8b264ffdf (the pie's CONTROL-POINT BOUND in place of R: each slice's arc as 90-degree cubic segments from the slice start, the
bound = the furthest any anchor/control point reaches along an axis; zh-37b6536f 99.3 -> 100). All paired clean (one accepted
drop, since recovered). lo-f9b9a8fc is 87.5 (7/8): label 5 (202.5 deg, layout B at frame 480-488 px) is the one miss.

What is known about the miss: see the sections below. In one paragraph: Word's auto place = an internal DEFAULT (mirror-symmetric;
the box corner nearest the centre on a ring R + 5.0 pt, 2.8-3.9 deg clockwise of the slice middle; found by pinning labels with a
zero manualLayout, lab piepin) plus a PULL toward the rim point / nearer axis whose size depends on the whole label set: lone zone
label 1 is pulled 31 px to the vertical axis, with other labels 4-30 px; label 5 alone 0, with others +13..+36. Only labels whose
slice middle is 13-30 deg from vertical interact; the result is deterministic per chart, order-dependent, independent of px phase,
piecewise constant in a partner's anchor class, not additive, and (advisor round 4) NOT explained by any contact/corridor stop,
budget, angular-gap rule or slot search (pulls get LONGER with partners, so no obstacle rule can work). Worse: a lone zone label is
not mirror-consistent (-29..+19 px between a label at m and at 360-m, random sign), so the unknown is the SINGLE-label process.
No overlap resolution exists at all (zh-37b6536f stacks five labels on top of each other).

DECIDED by lab pinsweep (2026-11-07 ~10:15 UTC, section "Lab pinsweep read" below): Word's pinned DEFAULTS are smooth and mirror-exact; its
AUTO places jump 3-39 px between half-degree steps and differ from their mirrors by 9 px median / 20 max (32 of 39 angles). The pull is a chaotic
step search, so no lone-label pull rule is written: the landed rule stays and lo-f9b9a8fc label 5 is released as unexplained (87.5), the
release decision with the user via starling-bd. Tools: test/lab/pie-fit/{load,configs,sim,compare,pinsweep}.py (now committed with this
note; configs.load() = every print; sim.score() = hits within 4 px; sim.snap assumes the pie centre 133.33 px below the frame top -
piezone2's is 143.73). Lab data: wip/lab-<lab>-prints branches, test/lab/<lab>/prints/*-WORD.tsv.

### Lab pinsweep read (wip/lab-pinsweep-prints f5535727, 164 of 164 docs; test/lab/pie-fit/pinsweep.py; 2026-11-07 ~10:15 UTC) - VERDICT: chaotic
One labelled 45-degree slice (R 60.43), its middle m at 12..31 by 0.5, auto and pinned (c:manualLayout 0/0 = Word DEFAULT), and the mirror (360-m).
Columns: text-left / top of the label box in px from the pie centre (mirror x negated so equal rows mean mirror-consistent); pull = auto - default; L = leader.
```
m      | default(l,t)  auto(l,t)      pull(dx,dy) ld | mirror: default    auto           pull       ld | auto-mirauto
12.0 |   +7.0  -96.3   -22.1  -94.3  -29.0  +2.0   |   +7.1  -96.3   -19.3  -93.3  -26.3  +3.0   |  -2.8  -1.0
12.5 |   +8.9  -96.1   -19.1  -95.3  -28.0  +0.8   |   +9.0  -96.1   -19.3  -93.3  -28.3  +2.8   |  +0.2  -2.0
13.0 |  +10.8  -95.9   -20.1  -95.3  -30.8  +0.6   |  +10.9  -95.9   -14.3  -95.3  -25.2  +0.6   |  -5.8  +0.0
13.5 |  +12.6  -95.8   -19.1  -95.3  -31.7  +0.5   |  +12.8  -95.8   -15.3  -95.3  -28.1  +0.5   |  -3.8  +0.0
14.0 |  +14.5  -95.6   -19.1  -95.3  -33.6  +0.3   |  +14.7  -95.6   -14.3  -95.3  -29.0  +0.3   |  -4.8  +0.0
14.5 |  +16.5  -95.4   -19.1  -95.3  -35.6  +0.1   |  +16.5  -95.4   -15.3  -96.3  -31.8  -0.9   |  -3.8  +1.0
15.0 |  +18.4  -95.2   +19.9  -92.3   +1.6  +2.9   |  +18.5  -95.2    +3.7  -93.3  -14.8  +1.9   | +16.2  +1.0
15.5 |  +20.3  -95.0   +22.0  -94.3   +1.7  +0.8   |  +20.4  -95.0    +6.7  -92.3  -13.7  +2.8   | +15.2  -2.0
16.0 |  +22.2  -94.8   -14.1  -95.3  -36.2  -0.5   |  +22.3  -94.8    -5.4  -93.3  -27.6  +1.6   |  -8.7  -2.0
16.5 |  +24.1  -94.7   -14.1  -95.3  -38.2  -0.6   |  +24.2  -94.7    +5.7  -92.3  -18.5  +2.4   | -19.8  -3.0
17.0 |  +26.0  -94.4    -9.1  -95.3  -35.1  -0.9   |  +26.1  -94.4    +1.7  -92.3  -24.4  +2.1   | -10.8  -3.0
17.5 |  +27.9  -94.2    +2.9  -93.3  -25.0  +0.9   |  +28.1  -94.2   +20.7  -91.3   -7.5  +2.9   | -17.7  -2.0
18.0 |  +29.9  -94.0    +2.9  -92.3  -26.9  +1.7   |  +30.0  -94.0    +7.7  -92.3  -22.3  +1.7   |  -4.8  +0.0
18.5 |  +31.7  -93.8   +16.9  -94.3  -14.8  -0.5   |  +31.8  -93.8   +17.7  -92.3  -14.1  +1.5   |  -0.8  -2.0
19.0 |  +32.4  -93.5   +16.9  -94.3  -15.5  -0.7   |  +32.4  -93.5   +18.7  -92.3  -13.7  +1.3   |  -1.8  -2.0
19.5 |  +33.1  -93.3   +18.0  -93.3  -15.1  +0.0   |  +33.1  -93.3   +18.7  -91.3  -14.4  +2.0   |  -0.8  -2.0
20.0 |  +33.7  -93.1   +18.9  -93.3  -14.7  -0.2   |  +33.9  -93.1   +31.7  -88.3   -2.2  +4.8   | -12.8  -5.0
20.5 |  +34.4  -92.8   +19.9  -92.3  -14.5  +0.5   |  +34.6  -92.8   +32.7  -87.3   -1.9  +5.5   | -12.7  -5.0
21.0 |  +35.1  -92.5   +19.9  -92.3  -15.2  +0.3   |  +35.2  -92.5   +33.6  -86.3   -1.6  +6.3   | -13.7  -6.0
21.5 |  +35.8  -92.3   +20.9  -91.3  -14.9  +1.0   |  +36.0  -92.3   +33.6  -86.3   -2.3  +6.0   | -12.7  -5.0
22.0 |  +36.5  -92.0   +22.0  -91.3  -14.6  +0.7   |  +36.6  -92.0   +18.7  -91.3  -17.9  +0.7   |  +3.2  +0.0
22.5 |  +37.2  -91.7   +10.0  -92.3  -27.2  -0.6   |  +37.4  -91.7   +18.7  -91.3  -18.6  +0.4   |  -8.8  -1.0
23.0 |  +37.9  -91.4   +16.9  -93.3  -21.0  -1.9   |  +38.0  -91.4   +19.7  -90.3  -18.3  +1.2   |  -2.8  -3.0
23.5 |  +38.5  -91.1   +18.0  -93.3  -20.5  -2.1   |  +38.7  -91.1   +20.7  -90.3  -18.0  +0.9   |  -2.7  -3.0
24.0 |  +39.2  -90.8   +30.9  -92.3   -8.3  -1.4   |  +39.3  -90.8   +22.7  -90.3  -16.6  +0.6   |  +8.2  -2.0
24.5 |  +39.9  -90.6   +30.9  -91.3   -9.0  -0.7   |  +40.1  -90.6   +22.7  -90.3  -17.3  +0.3   |  +8.2  -1.0
25.0 |  +40.6  -90.2   +19.9  -91.3  -20.7  -1.1   |  +40.7  -90.2   +23.7  -89.3  -16.9  +1.0   |  -3.8  -2.0
25.5 |  +41.3  -89.9   +36.9  -91.3   -4.4  -1.4   |  +41.4  -89.9   +24.7  -89.3  -16.7  +0.6   | +12.2  -2.0
26.0 |  +41.9  -89.6   +38.0  -91.3   -3.9  -1.7   |  +42.1  -89.6   +27.7  -90.3  -14.3  -0.7   | +10.2  -1.0
26.5 |  +42.6  -89.3   +38.9  -90.3   -3.6  -1.0   |  +42.7  -89.3   +22.7  -91.3  -20.0  -2.0   | +16.2  +1.0
27.0 |  +43.2  -89.0   +38.9  -89.3   -4.3  -0.3   |  +43.3  -89.0   +23.7  -90.3  -19.6  -1.3   | +15.2  +1.0
27.5 |  +43.9  -88.6   +40.0  -89.3   -3.9  -0.6   |  +44.1  -88.6   +24.7  -90.3  -19.4  -1.6   | +15.3  +1.0
28.0 |  +44.5  -88.3   +41.0  -88.3   -3.6  +0.0   |  +44.7  -88.3   +24.7  -89.3  -20.0  -1.0   | +16.3  +1.0
28.5 |  +45.2  -87.9   +41.0  -87.3   -4.2  +0.6   |  +45.4  -87.9   +25.7  -89.3  -19.6  -1.3   | +15.2  +2.0
29.0 |  +45.8  -87.6   +42.0  -87.3   -3.8  +0.3   |  +46.0  -87.6   +26.7  -88.3  -19.3  -0.7   | +15.2  +1.0
29.5 |  +46.4  -87.2   +53.0  -89.3   +6.5  -2.1 L |  +46.6  -87.2   +42.7  -87.3   -3.9  -0.1   | +10.2  -2.0
30.0 |  +47.1  -86.9   +53.0  -88.3   +5.9  -1.4 L |  +47.3  -86.9   +42.7  -84.3   -4.5  +2.6   | +10.2  -4.0
30.5 |  +47.7  -86.5   +42.0  -84.3   -5.7  +2.2   |  +47.9  -86.5   +42.7  -84.3   -5.2  +2.2   |  -0.8  +0.0
31.0 |  +48.3  -86.1   +42.9  -83.3   -5.4  +2.8   |  +48.6  -86.1   +43.7  -83.3   -4.8  +2.8   |  -0.8  +0.0
```
- DEFAULTS are smooth and mirror-exact: 0.7 px median step in x, 0.3 in y, max 2.0 px, no jump > 3 px in 38 steps; default vs mirror default within 0.2 px everywhere.
- AUTO places are NOT: 13 of 38 half-degree steps jump > 3 px (max 39 px, e.g. 14.5 -> 15.0: -19 -> +20 px, 15.5 -> 16.0: +22 -> -14), the mirror
  auto jumps at 15 of 38 steps at DIFFERENT angles, and auto vs mirrored auto differs by 8.9 px median, 20 px max, > 3 px in 32 of 39 angles.
  The pull takes a handful of discrete values (about -36, -27, -20, -15, -9, -4, +2, +6 px) with no monotone or periodic law in m; two auto labels
  (29.5, 30.0, not their mirrors) get a leader at 1.3 px pull. No stop at the slice start edge, no circle-contact stop, no smooth function of the default.
- By the agreed criterion (advisor round 4): the pull is a chaotic step search inside Word; a lone zone label cannot be predicted from the geometry, so
  the landed 30/60 rule with its 0.75 zone fraction STAYS and no lone-label pull rule is written. lo-f9b9a8fc label 5 released as unexplained (87.5),
  pending the user. The pinned-only extras give the default law in general (nearest box corner at 1.09-1.13 R, 1.4-4.1 deg clockwise of the middle above
  the horizontal and 0.5-2.7 anticlockwise below it; the same for spans 30 and 60 at 22.5); nothing to build from it until a doc pins labels with 0/0.

# Round 3 (lenovo-2, 2026-11-07, in progress): the raster, Word's box, and lab pie1

Scripts: `test/lab/pie-fit/` (load.py reads every lab's TSVs; draw.py draws a print's boxes; pie1.py reads lab pie1).

Facts added to rounds 1-2 (all 104 prints):
1. **Word lays the chart out on a 96-dpi raster from the frame's top left.** Every label text box's left and top are
   whole pixels there; the pie centre is at exactly W/2 px (fractional) and 100.0 pt (133.33 px) below the frame top in
   the 212.25 pt frames. The 3 pt period in x is the centre's sub-pixel phase; the y values are the whole pixels.
2. **Word's label box is the text advance box with Calibri's 0.952/0.269 em line (10.99 pt at 9 pt), no insets**: the fitz
   box (typo 0.75/0.25) with its top 1.8 pt higher and its bottom 0.25 lower. With that box, every undisturbed label in the
   pieang prints has a corner or an edge middle on the rim point within 0.2 pt, by a sector table: bottom-centre within
   12.5 deg of twelve, bottom-left corner 25-60, left edge 62-103, top-left corner 122-148, top-centre 167-193, then the
   mirror. Labels below the pie stand 1.2-2.6 pt lower than that, top ones 0.2 above. The side labels' inner edge is at
   x = +-R (the pie's bounding square), not at the rim point's x.
3. The 8-slice chart's labels all sit on the sector edges (22.5 + 45k). In it the top labels keep their y (box bottom 1-2 px
   below the pie's top) and slide in x; the side labels keep x (inner edge about +-R) and slide in y; the bottom labels keep y
   and slide in x. Which way and how far depends on which other labels exist, including far ones: removing label 7 moves
   labels 8, 1 and 2 by 8-11 px (toward twelve o'clock, i.e. toward each other); label 1 alone (no8) sits at its corner anchor,
   label 8 alone (no1) 15 px toward twelve o'clock with its bottom-right corner on the circle; layout C's label 1 also has
   that corner on the circle (a bottom-centre anchor pushed out until it clears the pie).
4. The layouts A/B/C are functions of the frame width in whole px (A <= 479, B 480-488, C >= 489; w400 is a fourth), yet
   nothing is near a wall: the label extremes vary print to print (top 45-50 px, bottom 218-224 px of a 283 px frame), the
   legend is centred, the pie is at W/2. No candidate wall (frame fraction, square plot, legend) fits.
5. R does not depend on the labels (only5, lab7, lab11 all 53.76). (The apparent variation with the slice angles was the Bezier
   control-point artefact above; amd-1's 0.875 x room - 1.37 stands.)

Lab pie1 (wip/lab-pie1, 208 docs, sent to windows 2026-11-07): one label alone at 159 angles (5-degree grid, 1-2 degree
scans at the sector edges), all 28 label pairs at ang 0 (index order = placement order), the full chart at widths 370-450.
It gives the anchor function and circle clearance, the pairwise interaction with its direction and order, and the layout bands.
Until it is printed no rule is written; lo-f9b9a8fc stays 87.5.


### Round 3, after lab pie1 (159 lone labels, 28 pairs, 21 widths; TSVs on wip/lab-pie1-prints) and the Opus advisor

Lone labels: exact (0.2 pt) corner/edge-middle-on-the-rim placement by a 30/60-degree table measured from the vertical axis
(centred within 30 of vertical... in detail: bottom-centre to 12.5 deg, corner 25-60, side 61-116 with the inner edge at x = +-R,
corner 119-150, top-centre 167-193, mirrored), the pie allowed to poke up to ~1.5 px into the box. Within 13-30 deg of the vertical
axis (22.5, 157.5, 202.5, 337.5 +-7) even a LONE label is erratic: the box rests on the pie's top/bottom tangent line and its position
along that line between "centred on the rim point" and "corner on the rim point" jumps from one degree to the next (fractions 0.44,
0.56, 0.62, 0.61, 0.26, 0.99, 0.98, 0.22, 0.53, 0.27 for 15.5..24.5); at 207.5 a lone label gets a leader line 13 pt clear of the pie.
Pairs: side labels (2,3,6,7 at 67.5/112.5/247.5/292.5) never move each other (0 px in all six pairs); diagonal labels move 10-36 px
whenever any other label exists, even one across the pie, always along their tangent line: label 1 (22.5) moves +27 px (to its corner)
with partner 2, 4, 6 or 8, +16 with 3 or 7, +1 with 5 (which then gets a leader); label 5 (202.5) moves toward 6 o'clock by 13 (with 4),
17 (6), 20 (8), 24 (7), 27 (2, 3). The amount depends on the partner's index parity / angle mod 90, not on distance. Lone and pair
positions do not change with the frame width (only5, p45 at w350/w360 identical to the px phase); the 8-label layout does (bands
A <= 479 px, B 480-488, C 489-497, E ~498-503, D 504-573 stable to w430; one legend row from w434).
Leader lines: every leader stands >= 7.8 pt from its rim point, but narrow-frame side labels stand 8-13 pt away without one.
CORRECTION (amd-1, 2026-11-07): the 'R depends on firstSliceAng' series (53.76-55.62) was meas.py's wedge-box extent, which includes the arcs' Bezier control points (R x 1.0346 for 45-degree arcs, cos-projected); Word's drawn radius is flat in angle. What stands is that the lone labels in pie1 sit EXACTLY (0.3 pt) on that control-point radius, not on the drawn circle: at firstSliceAng 15 the corner is 1.86 pt beyond the true rim. So Word anchors its labels on the pie path's bounding box (control points included), a square for equal 45-degree slices; for other slice sizes the box is not square (5 equal slices: 1.085 R across, 1.064 R up and down) - lab pie3 asks which. The rule landed uses the drawn radius (right for lo-f9b9a8fc's ang 0).
amd-1 (2026-11-07) RETRACTED: there is no radius law. Word's pie radius does not depend on firstSliceAng. The "53.76 .. 55.62" series (and my cos(d) fit of it) measured Bezier CONTROL points: a circle drawn as arcs of angle t has control points at R*sqrt(1+k^2), k = 4/3*tan(t/4) (1.0346 for 45 degree arcs, 1.0153 for 30, 1.0898 for 72, 1.1424 for 90), so the farthest-point or box radius wobbles with where the arc ends fall. Lab pie3 (windows' rc.py, wip/amd1-pie3-prints) read right: R 54.54 (12 slices), 55.58 (8), 65.87 (5), 69.05 (2) divide by those factors to 53.72 / 53.72 / 60.44 / 60.44 - flat in angle. Measure radii from on-curve points only (first and last point of each curve item) or a circle fit. Our own pies, measured that way (a0): 53.70 / 53.70 / 60.44 / 60.44 - labelled Word pies are already right at every slice count. Open: label-less pies with a legend at the foot, Word 62.96 (8 slices) and 70.65 (5) after the factor, ours 68.85 and 74.18.

Opus advisor (scratchpad advisor/, 2026-11-07): no exact algorithm recovered. Best explanation: an iterative whole-pixel search over
all labels together that also accepts equal-score moves, so labels drift along their equal-cost tangent line for as long as the loop
runs, and any other label that keeps the loop running lengthens the drift (explains exact anchors elsewhere, erratic lone labels,
long-range coupling, whole px); the drift lengths could not be reproduced (112-116 of 159 lone labels at best). Fallback rule
(30/60 table, px snap, push out until overlap <= 1.5 px, 0.75 of the way centre->corner within 13-30 deg of vertical, bottom labels
1.5 px lower): pie1 242/373 and earlier 366/740 within 3 pt, against 148/279 for today's rule; it still misses label 5 of lo-f9b9a8fc.
Not implemented (user: no tuned rules).

Lab pie2 (wip/lab-pie2, 116 docs, sent to windows): the 8-label chart at widths 356-376 with NO legend / legend right / no title (do
the width bands come from the legend or title?), three identical charts per page (does state carry over?), triples and quads (do the
pair moves add?), the lone 22.5 label across widths 350-370 and with names of 2-20 characters (px or box-fraction drift?), pairs 1-2
and 1-5 at firstSliceAng 5/10/15.


### Lab pie2 read (wip/lab-pie2-prints, 113 of 116 docs; the three 3-chart docs would not open in Word)
- The interaction between labels exists ONLY in the 13-30 deg flat zone: pairs 1-2 and 1-5 at firstSliceAng 5/10/15 (label 1 at
  27.5/32.5/37.5, outside the zone) put both labels exactly where they stand alone (0-1 px), and the lone leader at 207.5 goes away
  with label 1 present. Outside the zone a label's place is its own; inside it, other labels move it.
- Triples do not add or take the max of the pair moves: label 1's move (px) alone 0; with 2: +27, 3: +16, 4: +27, 5: +1, 8: +27;
  with 2+3: +15, 2+4: +18, 2+5: +23, 4+5: +9, 5+8: +2, 2+4+5: +13, 4+5+8: +14. Label 5's: with 4: +13, 6: +17, 2: +27; with 4+6: +17,
  2+4: +27, 1+4: +21, 1+2: +24, 1+8: +26, 1+2+4: +16, 1+4+8: +6. A deterministic but tangled function of the set.
- A lone label in the zone does not depend on the frame width at all (label 1 at 22.5 deg, widths 350-370: dx +25.9..+26.5 pt, the px
  phase only). Width bands exist only for the full 8-label chart.
- Without the legend (R 70.49) or with it at the right (70.47) or without the title (65.17) the pie grows, four labels go inside, and
  the remaining outside labels are the same at every width 356-376: no bands. Not decisive about the legend's role (the geometry changed).
- A lone label's place depends on its own width as expected (names of 2-12 characters; the 2- and 4-character labels fit inside).
Conclusion for lo-f9b9a8fc's label 5: it is a zone label in an 8-label set; its place is set by Word's joint search, which these
labs still do not expose. The fallback rule is implemented (wip/pie-bestfit) per starling-bd's decision; label 5 stays open.


### Lab pieanchor read (wip/lab-pieanchor-prints, 66 docs, true R from the on-curve circle fit) and advisor round 2
- Word's corner and edge anchors sit on a ring about 2 px OUTSIDE the drawn circle, not on it: 12-slice pie (R 53.71) corners at
  1.023-1.034 R, 6-slice (R 60.44) 1.023-1.035, and pie1's side labels' inner edge at 1.027-1.039 x P.x (R_true 53.71). The pie1
  "exact on R_meas" was this ring seen through the control-point artefact. The landed rule anchors on R (2 px short) - cheap fix pending.
  Zone labels (13-30 deg) keep their box on the TRUE tangent (bottom at -R, pokes <= 1 pt).
- Narrow slices: a lone label of a 30-degree slice at 24-42 deg has its corner on the ring at the slice START + 22.5 deg, not at the
  middle (7 docs); 60-degree slices at the middle. So the anchor angle looks like start + max(span/2, 22.5). A lone 30-degree slice
  label at the BOTTOM (165-192 deg) is not drawn there at all: Word stands it beside the pie on the left (box top-right corner at
  247-280 deg, about theta + 82), no leader line. 3- and 5-slice pies (R 60.44) put every lone label inside; nothing to read.
- Advisor round 2 (scratchpad advisor2/): the pair/triple numbers rule out plain "drift as long as the loop runs" (triples never
  reach the larger pair drift: 2+3 -> 15, 2+4 -> 18, 4+5 -> 9 against 27) and every one-counter / last-label / add / max scheme; and
  they show a MODE SWITCH: with any zone label present every label of the chart is placed again, side labels moving 2-11 px to
  WORSE spots (further from their rim point) - without a zone label the per-label rule is exact. What survives: a search with
  richer carried state, or a chaotic/seeded trial-move search. Its ranking of labs: the partner sweep WITH controls (each partner
  alone and label 1 alone at every step, sweep to 190 deg), then the three-copies test, then partner width.
- Lab piezone2 (wip/lab-piezone, test/lab/piezone2, 171 docs) sent: both / one / two at s = 5..145 by 2.5 (partner middle 50-190).


### Lab piezone read (wip/lab-piezone-prints, 51 docs)
- Three identical charts in one document give identical layouts (all 8 labels, the lone 22.5 label, the pair 1-2): no state
  carries over between charts; the B layout (label 5 at -54.4,+52.5 with its leader) reproduces exactly. Deterministic per chart.
- ORDER decides: pair (1,2) at firstSliceAng 0 (zone label first) puts label 1 at dx +46.2 (its corner end) and label 2 at +77.7,-21.0;
  the same geometry at firstSliceAng 45 with the zone label SECOND (labels 8 at 22.5 and 1 at 67.5) puts the zone label at +28.2
  (2 pt from its lone +25.9) and the side label 3.7 pt higher (+77.7,-24.0). Zone second with a 112.5 partner: +39.4 (first: +37.9);
  with a 202.5 partner: +45.4 and the partner at -40.1,+58.5 with no leader (first: +27.2 and the partner moved 36 px with a leader).
- Pixel phase (widths 360-360.75) changes nothing. A partner's name of 12 characters changes nothing; a partner of 2 or 6 characters
  goes INSIDE the pie and still moves the zone label (to +49.2,-54.0); 20 characters wrap and shrink the pie.
- Partner sweep (3 slices, R 60.5, labels 56.5 pt wide): the zone label's text-left is a STEP function of the partner's sector, not of
  its angle: partner at 50-60 deg (corner-anchored) -> +24.9 px; 62.5-75 (side-anchored) -> +7.9; from 77.5 on (the partner's row is
  missing from the TSV, probably inside) -> +10.0; constant within each plateau. Controls (each label alone) are in piezone2.


### Lab piezone2 read (171 docs; 3 slices, R 60.5, labels 56.5 pt; wip/lab-piezone-prints)
- A lone zone label (22.5 deg) is the same, (text left +10.0, top -94.7 px of the centre), whatever the other slices' angles: the
  lone position depends on the pie and the label only.
- Partner corner-anchored (50-60 deg): the zone label moves +15 px toward its corner and 2 px down (265, 51 from 250, 49 in
  frame px); the partner stays exactly where it stands alone. Partner side-anchored (62.5-75): the zone label moves 2 px LEFT and 2
  up (248, 47), and it is the PARTNER that moves, to a box top of 92, 102 or 112 px from the frame top (101 once), 30/40/50 px
  under the zone label's bottom, from lone tops 98-115 that follow its angle: a 10 px grid relative to the zone label. Partner
  inside the pie (from 77.5 deg) or absent: the zone label is at its lone place; an inside partner has no effect here (it did in
  piezone's width test with the 8-slice pie).
- Still no mechanism: deterministic, order-dependent, piecewise constant in the partner's sector, with px-grid destinations.


### Lab piepin read (33 docs: one label at a time given a c:manualLayout offset) and advisor round 3
- A pinned label still takes part: pinning ANY label with a zero offset changes the other seven (label 5 moves 13-25 px right and
  9 px down from layout B, its leader gone in half the cases); the pinned label's drawn position does not matter (offsets 0 / right
  / up / far give the same others, except where the far box lands on another label). Pinned is not deleted (no1 differs from k1).
- The zero-offset positions are Word's internal DEFAULTS, and they are perfectly mirror-symmetric (text-left, top px from the
  centre): 1 (33.5, -85.5), 2 (74.2, -39.7), 3 (74.2, 25.0), 4 (33.5, 70.8), 5 (-96.8, 70.8), 6 (-137.5, 25.0), 7 (-137.5, -39.7),
  8 (-96.8, -85.5): side labels' inner edge at R + 1.9 pt and their middle 3.7 pt beyond the rim point's y; top/bottom labels' near
  edge 1 px inside the tangent and their box corner 4.8 pt beyond the circle. The AUTO result is default + an inward adjustment that
  depends on the context: lone label 1 -30.5 px (to the axis: its box with insets ends at x = 0), lone 4 -8.5, lone 5 0, lone 8 +7.7,
  side labels 4-6 px inward and 3-4 px toward the horizontal axis; in layout B: 1 -7.6, 4 -13.6, 5 (-7.3, -9.2) with the leader, 8 +10.7.
  So the "drift" is the size of this pull, largest when alone.
- Advisor round 3: no candidate-slot / clearance search fits (26,880 variants; the best never triggers). The zone label's outcome is a
  function of the partner's anchor CLASS (absent/inside: lone; corner: +15 px; side: -2/-2), not of its box; corner partners are
  frozen; re-placed side labels sit ~1.6-2.6 px further out and slide 2-9 degrees along the rim. Its reading: a sequential process whose
  state changes with the work each label causes. Notes: sim.snap's 133.33 px centre is wrong for piezone2 (143.73); score zone cases at 1.5 px.


### In the default frame (8-slice ang 0 chart, R 53.76, labels 47.4 pt; pulls in px from Word's defaults above)
Every auto label is pulled from its default toward its rim point / the nearer axis; the pull size is the whole story:
- zone label 1 (22.5): alone -31; with partner 5: -30; with 3 or 7: -15; with 2, 4, 6 or 8: -4.  Layout A -8, B -8, C -19.
- zone label 4 (157.5): alone -9; with 2, 3 or 8: -9/-10; 7: -13; 5: -18; 6: -19; 1: -28.  A/B -14, C -4.
- zone label 5 (202.5): alone 0; with 4: +13; 6: +17; 8: +20; 7: +24; 2, 3: +27; 1: +36 (leader).  A +29, B (-7, -9) leader, C +11.
- zone label 8 (337.5): alone +8; with 1, 2, 6: +8; 3, 7: 0; 5: +11; 4: +29.  A/B/C +11.
- side labels: alone (-6, +4) / (-6, -3) / (+4, -3) / (+4, +4) (inward and toward the horizontal axis); with others 1-6 px different.
- pinning label k (any offset) changes the others' pulls by up to 20 px, e.g. k1 pinned: 4 -> -30, 5 -> +6, 8 -> +15.
So a partner can leave a zone label's pull unchanged (1 <- 5; 4 <- 2, 3, 8; 8 <- 1, 2, 6) or cut it to a few px (1 <- 2/4/6/8).
Open question for the advisor (round 4): what limits the pull - a corridor, a budget, an order-dependent iteration.

# Round 2 (after pielabel5 and pielabel6): verdict

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

---

## amd-1 2026-11-06: after the y change (a47956dbe), per-angle x and y on our renders v Word's prints

Our renders of pielabel5 (29 docs) and pielabel6 (47 docs), 562 labels, each against Word's print (label centre minus its own pie centre). Angle = label centre's angle, clockwise from 12 o'clock, nearest 22.5. "x ok" = within 3 pt in x.

| angle | n | median ours-Word dx | x ok | median dy | y ok |
|---|---|---|---|---|---|
| 22.5 | 38 | +6.0 | 9 | -0.9 | 29 |
| 45 | 31 | -2.3 | 28 | -0.9 | 30 |
| 67.5 | 60 | 0.0 | 60 | -1.9 | 48 |
| 90 | 9 | -0.6 | 9 | -9.7 | 0 |
| 112.5 | 69 | -1.0 | 57 | +0.1 | 48 |
| 135 | 22 | -5.2 | 0 | +1.9 | 12 |
| 157.5 | 51 | +2.7 | 30 | +0.8 | 51 |
| 202.5 | 37 | -8.7 | 6 | 0.0 | 37 |
| 225 | 38 | +13.4 | 13 | +3.0 | 11 |
| 247.5 | 69 | +1.1 | 51 | +0.1 | 53 |
| 270 | 2 | +6.4 | 0 | -9.7 | 0 |
| 292.5 | 67 | +0.3 | 59 | -0.4 | 40 |
| 315 | 52 | -0.3 | 43 | -1.6 | 43 |
| 337.5 | 17 | -0.9 | 11 | -0.9 | 16 |

Reading: the 135 bucket is all one cause, label 4 in Word's layout C (frame 489 px and wider: Word +45.5, y 58.5; ours +40.9, 61.5) and in the 470-490 pt frames (Word +49.0, y 65.8; ours +43.5, 67.7; our pie radius there, 60.49, is already Word's). 202.5 and 225 are label 5 and its neighbours across Word's layouts A, B, C and the narrow frames. No narrow x rule written: each is one label of one layout of Word's joint layout (see Round 2). Overall on these 562 labels: x and y within 3 pt 303 (54%), y within 3 pt 418 (74%).
