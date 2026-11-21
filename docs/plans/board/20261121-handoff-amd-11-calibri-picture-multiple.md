# amd-11 handoff: picture line under a line multiple, Calibri (sa1 6f0b70eb)
- 6f0b70eb: 70 to 75 of 84 lines (mean |dy| 0.200 to 0.137). a8f4dfcd 57/58 and afbaab24 40/49 unchanged.
- Two changes in the object-line multiple rule (RichLayout+Paragraph.swift): (1) "picture taller than the text line" now means more than 5% taller (was 0.5 units of a scaled measure, so a 13.5 pt picture in 13.3 pt Calibri counted as tall); (2) Calibri's depth under the baseline is its win descent 550/2048 em (2.96 pt at 11), not the engine probe's 2.29.
- Left: 6f0b70eb p4 spacer-paragraph gaps (lines 50-51, 62-63). Tall-picture threshold (5%) sits between two data points (13.5/13.3 fits the new formula, a8f4dfcd 20/14 the old one): a lab with pictures 14 to 18 pt would pin it.
- Unit tests: 836 run; 2 column tests failed from the real-columns merge (fixed upstream by 2d656da79), not from this change.
