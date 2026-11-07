Lab verdana-ls (amd-7, for windows): in/V.pptx = 24 slides; slide N = row N of in/cells-V.tsv (face, size pt, line spacing %). Faces Verdana and Calibri (control), 18/28/40 pt, 80/90/100/110%.
Each slide has four 6 x 3 in outlined boxes (no insets): centred one line, top-anchored one line, bottom-anchored one line, top-anchored two lines ("Hamburg").
Please print V.pptx to PDF (Print to PDF, one page per slide); commit the PDF under test/labs/verdana-ls/prints/ on branch wip/lab-verdana-ls.
Question: where PowerPoint puts a Verdana baseline in a line under or over single (we are 1.2 pt high at 28 pt, 90%, in a centred line), against Calibri.

Follow-up lab verdana-ml (genml.py -> in/M.pptx, 12 slides, rows in in/cells-M.tsv): same boxes, but each slide has four: centred 2 lines, bottom 2 lines, centred 3 lines, bottom 3 lines ("Hamburg" per line); Verdana and Calibri, 18 and 28 pt, line spacing 110/120/150%.
Please print M.pptx to PDF as before; push the line-table TSV like V-WORD.tsv (baseline, bbox, font, size, text per line, per slide) to a -prints branch.
Question: for text over single, where PowerPoint puts the lines of a centred and a bottom-anchored block (does the last line's trailing extra drop for 2 and 3 lines too).
