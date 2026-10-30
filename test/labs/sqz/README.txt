Lab sqz — Word for Windows' squeeze-or-stretch choice at a justified line's end, outside zh-3c055c9b's grid. NOT for office.
What gs2 (landed as gridgap) already covers: on a character grid, mark type and language change nothing, mark count does, and the automatic
space between the line's end and the piece leaves with the piece. This lab tests what is left: the legacy modes (12/14) and no-grid lines.
Seven lines of the corpus where our decision and Word's differ (v2 census 2026-10-30; 33 of the 38 disagreements in ten documents are
"Word takes a piece ours refuses", mostly compressPunctuation, modes 12/14), each cut to a one-paragraph document in its own pPr and
section, then one variable at a time. See build.py's header for the lines and the forms F0..F10.
1. python build.py REPO OUT          (REPO = a checkout with test/corpus/docx/docs) -> 66 t-<line>-<form>.docx
2. Print each in a FRESH Word for Windows (quit between, none open), PDF named like the docx.
3. python meas.py OUT/t-*.pdf        -> per print: line 1's right end and last 8 characters, and line 2's first 8 (was the piece taken).
Send that output (and the PDFs). The F0 prints are the controls: they should take or refuse the piece as Word's original print does
(A, B, C, D, E: Word TAKES; F, G: Word REFUSES; A's line in Word ends "…联通眉山分").
