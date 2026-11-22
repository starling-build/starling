# amd-perf: fontAlgn ctr at 150%, fit with lenovo-5's #1624 ascent/descent box (lab tblrow2, no new lab)

Baseline below the line top, in em of the font size, 150% spacing, no cell margin, PowerPoint's print:
- Arial 24 pt: 1.546. MS PGothic 28 pt: 1.557.
- Fit: lenovo-5's ctr target, (1.2 - (asc+desc))/2 + asc, PLUS the full extra line space above the baseline, (m-1) x 1.2 = 0.60 at 150%.
  Arial: 0.9465 + 0.60 = 1.5465 (print 1.546). MS PGothic (asc .859, desc .141): 0.959 + 0.60 = 1.559 (print 1.557). Both within 0.1 pt.
- Without fontAlgn (rows 3, 4, 7) ours already equals the print to 0.0 pt, so the extra is the same there and the ctr box is the only change.
- Meiryo UI 24 pt: print 1.627, the formula needs asc - desc = 0.854 em for Meiryo UI (the Meiryo row in #1624 gives 0.62, a different face). Take Meiryo UI's own Windows ascent/descent from lenovo-5's lab7 if it has the UI face; not measured here.
- Only 150% is measured (m = 1.15 not); I assume the extra above is (m-1) x 1.2, not a constant 0.6.
- Plan: #1573 (row height, fontAlgn ctr, merged first) keeps cellFullFirstLine; lenovo-5's #1624 drop for ctr gets + (m-1) x 1.2 em when cellFullFirstLine is set. I will add that on top of #1624 once it merges, unless lenovo-5 prefers to.
