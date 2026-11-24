# amd-3: Meiryo UI 16/18 pt screen rows (HANDOFF)

Auto rows of empty 18 pt Meiryo UI cells printed 27.1 pt; Excel prints 25.6 pt (65 px). Screen rows for 16 and 18 pt set to 58 and 65 (3.5 px a point, as 12 to 14).
r3 sweep: ja-d9ac78f0cb 44.4 to 73.3, ja-61c6327da4 55.4 to 80.0, ja mean 76.65 to 77.09, 10 up, 1 down.
The one down, ja-32063d7d28 (11.7 to 6.0), uses no 16/18 pt: its layout is unchanged (same row-step histogram), page count 19 vs 20 already wrong. Not caused by this change; OPEN, wrong page count.
