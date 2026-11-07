Lab verdana-ls (amd-7, for windows): in/V.pptx = 24 slides; slide N = row N of in/cells-V.tsv (face, size pt, line spacing %). Faces Verdana and Calibri (control), 18/28/40 pt, 80/90/100/110%.
Each slide has four 6 x 3 in outlined boxes (no insets): centred one line, top-anchored one line, bottom-anchored one line, top-anchored two lines ("Hamburg").
Please print V.pptx to PDF (Print to PDF, one page per slide); commit the PDF under test/labs/verdana-ls/prints/ on branch wip/lab-verdana-ls.
Question: where PowerPoint puts a Verdana baseline in a line under or over single (we are 1.2 pt high at 28 pt, 90%, in a centred line), against Calibri.

Follow-up lab verdana-ml (genml.py -> in/M.pptx, 12 slides, rows in in/cells-M.tsv): same boxes, but each slide has four: centred 2 lines, bottom 2 lines, centred 3 lines, bottom 3 lines ("Hamburg" per line); Verdana and Calibri, 18 and 28 pt, line spacing 110/120/150%.
Please print M.pptx to PDF as before; push the line-table TSV like V-WORD.tsv (baseline, bbox, font, size, text per line, per slide) to a -prints branch.
Question: for text over single, where PowerPoint puts the lines of a centred and a bottom-anchored block (does the last line's trailing extra drop for 2 and 3 lines too).

Lab verdana-em (genem.py -> in/E.pptx, 8 slides, rows in in/cells-E.tsv: face, run size 24, spacing 100, END-PARAGRAPH MARK size 12/24/32/44): four boxes per slide: centred 1 line, top-anchored 1 line, bottom-anchored 1 line, centred 2 paragraphs (only the last carries the mark's size... both do).
Print E.pptx to PDF as before; the line table as E-WORD.tsv. Question: does the end-paragraph mark's size change a line that has text (its height, its baseline)?

Lab verdana-mf (genmf.py -> in/MF.pptx, 13 slides, rows in in/cells-MF.tsv): the word "Hamburg" in 1-3 runs of different faces/sizes, end mark in the last run's face or another face. Each cell is two boxes: left column centred, right column top-anchored; cell 2k+1 in the top row of slide k+1, cell 2k+2 in the bottom row. Print to PDF; line table as MF-WORD.tsv.
