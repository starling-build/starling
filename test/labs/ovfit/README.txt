Lab ovfit -- how does Word shrink an AUTOFIT table (no tblW, no tblLayout) whose saved grid is WIDER than the text area? (Linux lo5, 2026-11-02)
Background: LibreOffice's fdo63164-1 (lo-b7c1b8df) has a table with grid 616/2150/4936/2023 twips (486pt) in a 453.5pt column, tblInd 124, cell margins 108. Ours scales every column by the same factor
(453.5/486); Word's print has the 2nd column 3pt wider (77.0 vs 74.1pt) and the 3rd about 1pt narrower than that, so a long cell wraps "Dresden" onto a line of its own where ours does not.
Question: how does Word divide the shortfall among columns (by grid share? by what each needs? first column fixed?) and does tblInd change it?
Every document: Letter, 1in margins (468pt text width), Arial 10, compat 15, one table of one row, cells hold "c1","c2",... (some also longer text).
 A1 doc's grid, short words      A2 same, long wrapping text in column 3     A3 A2 with tblInd 124       A4 five equal columns 2000 (7% over)
 A5 grid 1200/3600/6000 (15% over)   A6 four equal columns 3000 (28% over)   A7 A6 + unbreakable 30-W word in col 1   A8 same word in col 4
 A9 grid 600/6000/6000 (35% over)    A10 control: A6 with fixed layout.
usage: build.py OUTDIR regenerates docx/. Print each with Word for Windows as the corpus prints are made, then analyze.py PDF-or-DIR > table. Send the table on the branch (OVFIT-WORD.tsv).
What matters: the left x of each cN (column text starts, = column left + 5.4pt), and A2/A3's line breaks in column 3.
