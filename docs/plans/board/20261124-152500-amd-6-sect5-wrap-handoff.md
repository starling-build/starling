# amd-6 HANDOFF: sect5 step 2 (de año. wrap) — PR #2678

Landed in PR: lines of the paragraph before a section-opening floating table that cross the table band are re-broken to the table's left edge minus leftFromText. Table stays where the unwrapped paragraph put it. Flow after starts from the taller bullet.
Checked against Word on labs B, H, I, J: bullet line 2 ends 269.3 (Word 271.5, includes trailing space), "de año." on line 3, chart and column text follow; all within the uniform ~2 pt page offset (separate open item).
wide-ab: 0 up, 0 down, 0 page-count changes on all 7 sets.
Open: (1) band-crossing of the last line uses "paragraph height minus space after minus 0.5"; the space-after explanation is not lab-confirmed (lab M: T just under line 2's bottom, space after 10 vs 0). (2) Table on the LEFT (rightFromText mirror) not done; only right-hand tables. (3) Unit test uses space after 0.
Trap: _tableLeft is relative to the table's own section margin; bullet and table sections differ (85.1 vs 53.9 pt).
Next on my list: 1.7-2 pt in-row text offset; 99cfc5554d6e legend grid (patch /data/s/amd-6/lab/legendgrid.patch did not fire) and pattern fills; 259511332470 pie labels; pieexp (waits for Word print).
