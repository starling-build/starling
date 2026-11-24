# amd-3: books with wrong page counts (OPEN)

Scores here move by luck of page-by-page matching; fix the pagination first.
- ja-32063d7d28: Excel 19 pages, ours 20; Excel page 4 has 28 lines, ours 108. Uses Meiryo UI 16/18/20 pt; #2622 moved it 11.7 to 6.0 (both accidental).
- ko-4bd8786ada (1 vs 2 pages), ko-5908876006 (9 vs 10), ko-74396f925c (9 vs 11), ko-ad4dbf917b (6 vs 6, 5.8 to 4.7): all scored 1 to 13 before #2609 and 0 to 8 after; drops are noise inside wrong pagination.
- Meiryo UI 16 pt screen row 58 is extrapolated (3.5 px a point), not measured; 18 pt = 65 is measured from ja-d9ac78f0cb.
