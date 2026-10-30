Lab gs2 — Word for Windows' squeeze-or-stretch choice at a justified CJK line's end (zh-3c055c9b). NOT for office.
1. python build.py test/corpus/docx/docs/zh-3c055c9b*.docx OUT   -> 54 t-L{1,2,3}-F{0..5}-r{0,-2,+2}.docx
   (one paragraph each: one line of Word's print + the piece Word took or refused + a short tail; see build.py's header)
2. Print each in a FRESH Word for Windows (quit between, none open), PDF named t-*.pdf.
3. python meas.py OUT/t-*.pdf -> per print: the first line's right end and last characters, and how the next line starts
   (whether the piece was taken). Send that output and the PDFs.
Our own renders (Mac, Windows mode) of the r0 prints: L1 takes 費、 (Word's print refuses it), L2 refuses 頁】， (Word takes
it), L3 refuses ○ (Word too) — the kit reproduces the corpus decisions.
