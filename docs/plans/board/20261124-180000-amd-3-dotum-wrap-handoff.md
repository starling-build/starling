# amd-3 — wrapped 돋움/굴림 lines: handoff (OPEN, not landed)

Branch w/amd-3/dotum-wrap (local, commit 8355ef0b90 on origin/main ec4251b5cd), A/B on sheets: 11 ko/xls books drop, no gains listed.

What is right (measured against Excel on ko-d7d378fab4):
- Excel's Dotum/Gulim wrapped line step is size + 1.2 pt (9.7 pt at 8.8 pt print; ours was 9.6 with the stand-in's 1.45 em).
- Dotum/Gulim had no ascent/descent entry, so every Dotum line sat about 0.1 em low. Entries 0.90/0.21 put single lines at -0.21 of Excel.
- The wrapped block's first line sat 2.2 pt low because the lines are drawn with their own fallback painter's baseline while y0 was computed from the "X" painter's. Drawing every line on the first line's baseline: heading 82.7 to 80.3 (Excel 80.5), "(VAT 제외)" 92.3 to 90.0 (Excel 90.3).
- Doing that drop for every face is WRONG: zh-1de4da4caa wrapped lines went from +0.95 to -1.69 off Excel (A/B: zh-1de4da4caa 100 to 60). So it is limited to Dotum/Gulim for now. Cause for other faces not found.

What still drops (A/B on origin/main ec4251b5cd): ko-42a497609b 100 to 83.3, ko-4fb28b444b, ko-5491765fc4, ko-0dc128b613, xls-0453e2c911, ko-bd08a67985, ko-6af1014e7e, 1_NoIden, ko-5cd059ba8a, ko-3c099ac411, ko-9b8e6da4cf.
- ko-42a497609b: Excel prints "※단체참가자명단작성..." as ONE line at y 77.28; ours now prints two lines (76.3 and 85.0). So in that cell the wrap decision, not the step, differs; the base matched. Next: find why a Dotum cell breaks into two lines with this change (suspect the printAscent/printDescent entries changing a width/height decision, or the pitch entering the row fit).
- Traps: wide-ab on a stale branch shows other people's merges as your drops (check git merge-base --is-ancestor origin/main HEAD first). wide-ab compares committed HEAD, not the working tree.
