Lab sqz3 — a width sweep of line G of lab sqz (zh-6b242483 p6: "B.对B级企业开展执法检查，共计36个工作日。9（家）|×1（每年1次）…", mode 14, LEFT-aligned, FangSong 16pt). NOT for office.
Word refuses the lone "×" at its own width and in every form of lab sqz (F8: × made an ideograph; F9: 2pt more room), while ours takes it
by squeezing ，。（） (need 5.1pt). Word's marks stay at a full 16.0 in that line. Left-aligned paragraphs of legacy-mode documents DO squeeze
marks in Word's prints (25% of 1,154 marks), so alignment is not it. This sweep finds the width at which Word first takes the ×: 12 prints,
the right margin stepped from 0 to -240 twips (12pt more room). That width is the line's squeeze budget.
1. python build_g.py REPO OUT     (REPO = a checkout with test/corpus/docx/docs)
2. Print each in a FRESH Word for Windows, PDF named like the docx.
3. python meas.py OUT/t-*.pdf  -> line 1's right end and last 8 characters, line 2's first 8 (was × taken).
   Send the PDFs of the first TAKEN width and the last REFUSED width: the marks' steps in them say how much each gave.
