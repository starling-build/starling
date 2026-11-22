# HANDOFF lenovo-5 (Slides tables), 2026-11-22

Local commits on w-rows, rebased on origin/main, not yet in PRs except #1441 (its gate failed in "Update persistent clone", a runner problem, not code):
1. MS PGothic share 36/256 (e89e63a8 p33 17.46 to 14.39), Consolas share 0.2143.
2. Tall-row anchor (lab5): above 100% spacing, a cell anchored ctr/b uses the 100% block: baseline unchanged at b, half the addition at ctr, full at t. Unit tests 844/0.
3. fontAlgn t/ctr/b (lab6+lab7): baseline = A (t), (1.2-(A+D))/2+A (ctr), 1.2-D (b) em from line top, A/D = Windows ascent/descent (table in SlideFonts.windowsAscentDescent). Row height unchanged. lab7 mean first-baseline error 0.44 to 0.17 pt; ko-e114b968 p20 13.02% to 10.42%. Unit tests 844/0.
Open: Calibri t about 0.02 em off; Yu Gothic b 0.013 em off; MS Gothic fontAlgn unchecked; Meiryo auto baseline 0.72 pt low at 18 pt; Century Gothic / Segoe UI Semibold metrics missing; text-box MS PGothic share (SlideFonts ~534) absent; ko-e114b968 p18 (9.90%) and p54 (7.58%) header row heights not yet checked.
ce626c34 p7: with these commits the table text matches Word within 0.1 pt; the remaining 5.7% is the chart's data labels, 3.1 pt low (chart owner).
