# amd-3 CVLKRA-KYC windows (whole-pixel model, 29 px/em, Excel print, first-line breaks of single-column wrapped cells)

Tool: /data/s/amd-3/sh/win7.py (cell strings from the book, column px = width x 15 floored, bold by cell style; only first-to-second line breaks, so the cell text is known). Result is noisy; read as a pointer, not a verdict.
- 105 px column (remarks): word breaks c0 in (6, 10]; mid-word breaks (9, 9], i.e. the line that fits has pad about 9, the line that does not fit about 9: pad 9 to 10 at 105 px whole-pixel. The merged fit's floor (11) leaves 1-2 px: lines of width 95 to 96 fit in Excel, ours breaks them (room 94).
- 222 and 690 px columns: windows inconsistent (many strings hold explicit line breaks or centred/bold runs); not usable yet.
- The 52716 columns (160 px) give (10, 12]. So the pad at 105 to 160 px is 9 to 12, which the labs also give (9/9/10/12 at 77/115/147/186). The floor of 11 was fitted to CVLKRA's remarks and 52716 rows together; the two books want different values at the same width, so the next step is not the formula but the per-row detail (the confirming lab: PR with lab/wrap-mid, 215 rows, 4 print scales).
- Hyphen hang landed in PR #1989 (CVLKRA 93.7 to 94.2).
