Lab tw1 — how Word for Windows sets the columns of a table whose second row has cells wider than the grid. NOT for office.
Question (starling-bd, for LibreOffice's tdf79329): a table with tblGrid 4536 + 1845, row 1 cells 4536 + 1845, row 2 cells 6381 + 6381, jc centre.
Word's print: the first column's text at x 57 (the left margin; the table is NOT centred), B1 and D1 both at x 310 (one shared column edge 253pt
in from the table's left, not the grid's 226.8). Ours centres a 319pt table. Which rule gives 253 and a flush-left table?
1. python build.py OUT        -> 8 documents tw-<orig|left|fixed|same|small|wide|one|pct>.docx (A4, margins 1134, text 481.9pt)
2. Print each in a FRESH Word for Windows (quit between, none open), PDF named like the docx.
3. python meas.py OUT/tw-*.pdf  -> per print: the table's vertical rules per row band and each cell's text x.
Read-out wanted: the table's left edge and each column edge for every variant (are rows 1 and 2 on one set of column edges? is the table
centred, left, or clamped?), and whether the total is clamped to the 481.9pt text width.
Control: tw-orig must print what Word printed for tdf79329: A1 at 57, B1 and D1 at 310.
