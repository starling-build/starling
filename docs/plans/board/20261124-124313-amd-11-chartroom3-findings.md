# amd-11 FINDINGS es-1dce05b4b2 (lab chartroom3, Word print 23 pages vs our 12)
Lab: lab/chartroom/chartroom3.docx; paragraph A (label), paragraph B (anchors a page-relative rectangle at y=40 pt, full text width less 7/40 pt room, height 300 or 700, wrapSquare/Through/Tight), paragraph C.
Word's rule (same for square, through, tight):
1. A page-relative float affects EARLIER paragraphs on the same page too, not only later ones. Case 0 (h300, room 7): label paragraph A (before the anchor paragraph) stands UNDER the box (y 340), then B, C follow. We put A at y 120 (before the box), so everything is 231 pt too high.
2. If the earlier lines pushed under the float, plus the anchor paragraph, do not fit the page (h700), the anchor paragraph moves to the NEXT page with its box; the earlier paragraph stays at its place on the old page (case 1: A on page 2 y 109, B+box on page 3 with its line at 741 under the box, C on page 4).
3. Room 40 pt: lines wrap into the 40 pt strip beside the box (one word per line), as we do.
Our paginator places a paragraph's own floats only after its line, so earlier paragraphs are never reflowed. A fix needs a page lookahead (register page-relative floats of the anchor paragraph before the earlier paragraphs on that page are laid out) and has no rewind mechanism today.
