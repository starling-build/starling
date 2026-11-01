Lab gq -- when does Word for Windows squeeze a line's marks to take one more character on a character grid? (zh-9c162f26; Mac 7bd18d8e, 2026-11-01)
Background: zh-9c162f26 (mode 14, compressPunctuation, doNotWrapTextWithPunct + doNotUseEastAsianBreakRules + balanceSingleByteDoubleByteWidth, docGrid
linesAndChars charSpace -842, 9pt, justified, in table cells) sets 44-character lines in Word's print: '4、装饰装修期间每3日巡查1 次现场，发现…违规行为的，' ends at the
44th and the 45th ('应') goes down. Ours squeezes the line's three marks 1.436pt each (4.31 in all) and takes it: 11 lines of the document, 16 squeeze
decisions in all (census: 214 'plain ideograph fit' line-end differences in the zh corpus, 118 ours longer, 96 Word longer; negative-charSpace documents lean
26:4 ours longer).  Word's own lines in that print squeeze marks by up to 3.4pt and take characters 11pt over elsewhere, so it is not 'no squeeze on a grid'.
The refused squeezes all sit in lines with digits (3, 1) and their automatic spaces (Word sets those 'stretched' 3.5-3.8pt where it justifies, ours 2.2);
the taken ones mostly do not -- but not all.  Tried on our side and refuted: (a) no mark give on a grid under doNotWrapTextWithPunct (zh-9c162f26 99.8 -> 70.6);
(b) a refusal by the mode-15 grid share formula with the line's spaces weighed 0.44 or 1.0 (zh-9c162f26 99.8 -> 92, zh-015abfaf 100 -> 43, zh-18cb2079 99.8 -> 72).
Method: gq.docx, 504 pages, 12 variants x 2 families x 21 pages (build.py makes it from the corpus' zh-9c162f26 package so the compat flags, grid and fonts are Word's).
One justified paragraph a page: 43 cells, then a 14-ideograph tail so it wraps; a cell is an ideograph, a digit '3' (D = 0,1,2,4 of them) or a '，' (M = 0,2,5).
w:ind right grows 0..20pt by 1pt a page, so the squeeze the line's last cell needs grows by 1pt a page.  Family b = the body (indent 70.7pt + R, text 371.55pt wide),
family c = the same paragraph in a one-cell table (cell text 371.55pt).  The count of characters on line 1 falls by one at each R where Word stops taking a cell:
with no marks (M0) that R is the slack; with marks, the difference is the squeeze Word accepts, and across D it is what the digits and their spaces cost.
Print gq.docx to PDF with Word for Windows, then  analyze.py gq.pdf > gq.tsv  (PyMuPDF; reads gq-index.tsv).  Send gq.tsv.  Our own print is GQ-OURS.tsv.
Read-out wanted: per variant the R of each drop; D0M0 vs D0M2/M5 (what marks give with no digits), then D1/D2/D4 (what digits change), body vs cell.
