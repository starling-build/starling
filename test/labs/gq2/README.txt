Lab gq2 -- gq's follow-up: a digit followed by a REAL space ("1 次") on a character grid (zh-9c162f26; Mac 7bd18d8e, 2026-11-01).
gq (windows' print, 2026-11-01) came back IDENTICAL to ours on all 24 variants (digit groups 0/1/2/4 x marks 0/2/5, body and cell): the drops fall at the same indent
to the point, so our squeeze model is right for a single digit with its automatic spaces, and the marks' give (6pt for 2 or 5 marks) too. What zh-9c162f26's refused
squeezes have that gq lacks: a real blank after the digit ("巡查1 次现场": Word sets the digit 4.32-4.44 and the blank 4.44, the ideograph before 13.2 for 8.8), and a
list-number "4、" opening the line. Method as gq (README there): same template, same ruler (indent 0..20pt by 1pt, count of characters on line 1), but a cell may be
'1 ' (digit + blank) standing where an ideograph would.  Variants D(digits) M(marks) S(digit+blank groups):  D0M2S0 (= gq's D0M2) S1 S2 S3, D0M0S1 S2, D2M2S1 S2.
Read-out wanted: the R of each drop vs GQ2-OURS.tsv (ours).  A difference in S1+ with marks means Word's blank after a digit changes what the line can give
(the "1 " pieces: set 8.8 together by ours; Word's 4.32 + 4.44, with the ideograph before it stretched).  analyze.py gq2.pdf > gq2.tsv (PyMuPDF; reads gq2-index.tsv).
