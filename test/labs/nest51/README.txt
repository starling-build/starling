Lab nest51 (for lo-51b81ccd): in compat 15 Word's nested table has its line centres 3 pt right of ours.
The doc has a nested table, tblInd -60, cell margin 85, 6 pt borders, in a zero-margin outer cell.
Print each docx/*.docx to PDF in Word (Windows), save as <name>-orig.pdf next to this README.
Docs (5 tables each, one variable per doc): ind15/ind12 = nested, tblInd -120..120; top15/top12 = same at top level;
bw15 = border width 0/0.5/3/6 pt; cm15 = cell margin 0/85/170 at tblInd -60; cmz15 = same at tblInd 0.
Read: python3 analyze.py x.pdf -> x of the text "T" and of the leftmost drawn rectangle per table.
Question: does tblInd shift the table edge or the text, nested vs top level, and does border width or cell margin move it?
