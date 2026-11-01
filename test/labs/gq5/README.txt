Lab gq5 -- is the half-em cut of gq3/gq4 a settings effect? (Mac 7bd18d8e, 2026-11-01)
gq4 (windows' print): on zh-9c162f26's linesAndChars charSpace -842 grid Word refuses the squeeze at less than half an em of room left (f9: 4.5pt; f12: R=3 where ours cuts at 4),
and with charSpace 0 or no character grid Word is ours to the point. zh-08e95de4 (same kind of grid: 11.8 cells for 12pt) takes characters with 1.1pt left, 10.7pt squeezed.
zh-9c162f26's settings.xml has w:noPunctuationKerning=1 and w:doNotUseEastAsianBreakRules; zh-08e95de4's has neither (both have compressPunctuation, useFELayout, balanceSingleByteDoubleByteWidth).
So: the SAME paragraph (line A in a one-cell table, jc both, the original -842 grid), 9 / 10.5 / 12pt, R = 0..12pt by 1pt, in five documents that differ in settings.xml only:
  s0 = the original | s1 = no w:noPunctuationKerning | s2 = no w:doNotUseEastAsianBreakRules | s3 = neither | s4 = characterSpacingControl doNotCompress
195 pages, 39 per document. s0 must reproduce gq4's gOrig rows (Word: f9 42 x13; f10 36 x9 then 35 x4; f12 32 x3 then 31 x10) -- if it does not, tell me first.
Print docx/gq5-s0.docx .. gq5-s4.docx with Word for Windows, then
   analyze.py gq5-s0.pdf gq5-s1.pdf gq5-s2.pdf gq5-s3.pdf gq5-s4.pdf > gq5.tsv      (PyMuPDF; reads gq5-index.tsv next to it)
and send the rows (variant, characters on line 1 at R = 0..12, line 1 at R=0). GQ5-OURS.tsv is ours (ours ignores these settings for this cut, so ours is the same in all five).
Reading: the document(s) whose f9 row stops dropping at R=0 / whose f12 cut moves to R=4 are the ones where the setting matters.
