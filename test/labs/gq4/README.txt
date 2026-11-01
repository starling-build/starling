Lab gq4 -- what sets the cut at which Word refuses a squeeze? (Mac 7bd18d8e, 2026-11-01)
gq3: zh-9c162f26's real line, 9pt, linesAndChars charSpace -842, one cell 371.55pt: Word takes the 44th character squeezing the line's three marks while 4.58pt is left
and refuses at 4.49 (half the 9pt em); ours has no such cut, and a general half-em rule drops 26 documents (other prints take characters with less room: zh-d8247da5
10pt/-1pt spacing/'lines' grid 4.95 left; zh-08e95de4 1.1 left). So gq4 sets the SAME paragraph with three things varied and crossed:
  FONT   9 / 10.5 / 12pt           (f9 f10 f12)
  GRID   linesAndChars -842 (the original) / linesAndChars charSpace 0 / 'lines' (no character grid)   (gOrig gCS0 gLines -- one DOCUMENT each, the grid is the section's)
  MARKS  the original (three on line 1) / none (every '，、' after the first two characters an ideograph)   (m3 m0)
R = 0..12pt by 1pt (right indent), jc both, one-cell table. 18 configurations x 13 = 234 pages, 78 per document.
Print docx/gq4-gOrig.docx, gq4-gCS0.docx, gq4-gLines.docx with Word for Windows, then
   analyze.py gq4-gOrig.pdf gq4-gCS0.pdf gq4-gLines.pdf --index docx/gq4-index.tsv > gq4.tsv     (PyMuPDF)
and send the rows (variant, characters on line 1 at R = 0..12, line 1 at R=0). GQ4-OURS.tsv is ours. For every configuration the R where the count first drops is the cut;
the interesting ones are where Word's drop comes EARLIER than ours (Word refuses a squeeze ours takes) and how that R moves with font, grid and marks.
If a page shows a drop in Word that ours does not, per-glyph x of line 1 for that page and its neighbour is what tells whether Word squeezed or stretched.
