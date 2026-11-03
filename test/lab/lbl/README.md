# lab lbl — lo-a197b7a8 (Note/Important labels in a single-cell table)

Question: Word's print of lo-a197b7a8 drops the label paragraphs (a framePr
wrap=notBeside paragraph, style AlertLabelinList1: picture + "Note ") lower in
most cells but NOT in the 5th single-cell table (p19-p20: Note, Important,
Important). The same markup in the 7th table (p21) IS dropped.

Each lbl-*.docx is the full lo-a197b7a8 with ONLY the 5th table changed:
style (labels -> AlertLabel), noframe (framePr removed), tblstyle (no table
style), mar (cell margins 108), tcw (tcW 8280), shd (cell shading), rpr (bold
label run), first (first label moved to the top of the cell), width0
(tblW 8856 dxa). The 7th table (dropped in the original print) is untouched in
every file, as the control. mk.py makes them.

Request: print each to PDF with Word for Windows (as lo-a197b7a8-orig.pdf was
made), name NAME-orig.pdf, push them to this branch under test/lab/lbl/word-win/.
We compare where the labels of pages 19-20 sit against the original print.
