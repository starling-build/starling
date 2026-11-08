# Print round 2 (Windows 01QbbApP)

Every set was printed a second time, 4-way parallel, in fresh Word instances, and compared with the first print:
page count plus every line's (page, baseline, x0, x1, text) to 0.01 pt. No PDFs are committed.

| set | compared | changed |
|---|---|---|
| A | see A-CHANGED.tsv | 4 |
| DX | | 4 |
| B | | 12 |
| B22 | | 2 |
| W (756 canonical refs) | | 42 (W2-CHANGED.tsv; the first W-CHANGED.tsv compared against a stale checkout and is omitted) |
| DX2 | 1825 | 14 (1 had no second print) |
| LO (593, against lab/lo/word-win) | 593 | 6 |

Word changed build in the middle of the day, 16.0.20527.20112 -> 20150 (WINWORD.EXE written 2026-11-07 12:16:40).
That is the likely cause of many of the W changes. Office auto-update was then frozen
(HKLM policy EnableAutomaticUpdates=0). Nothing tracked was replaced.
