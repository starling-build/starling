Lab sqz2 — a width sweep of line F of lab sqz (zh-360c1df1 p6, Word for Windows, mode 14, FangSong 16pt): NOT for office.
Word refuses the character "展" at its own width (F0) and takes it with 2pt more room (F9). Our squeeze takes it by giving the full stop 。
8.03 against a need of 7.93; in Word's F9 print 。 steps 10.0 (gives 6.0), both quotes (Times New Roman Bold, 0.5 em natural) give nothing.
This sweep reads Word's limit: the right margin stepped from F0's (0) to F9's (-40 twips) in 5-twip steps, with the 。 before 积极开 replaced
by 。 ， 、 ； to find the take/refuse threshold per mark. 36 prints.
1. python build_f.py REPO OUT      (REPO = a checkout with test/corpus/docx/docs)
2. Print each in a FRESH Word for Windows, PDF named like the docx.
3. python meas.py OUT/t-*.pdf  -> line 1's right end and last 8 characters, and line 2's first 8 (was 展 taken).
   Also send the PDFs of the first TAKEN and last REFUSED width for each mark: the steps of the mark and its neighbours say how much it gave.
