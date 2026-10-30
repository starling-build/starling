Lab sqz5 — the table cell or the alignment: which lets Word for Windows break between "×" and a digit? NOT for office.
See build_i.py's header. 12 prints: variants a (as is), j (justified), t (one-cell table), tj (both) x right margins 0, -60, -100 twips.
1. python build_i.py REPO OUT     (REPO = a checkout with test/corpus/docx/docs; build_g.py beside it)
2. Print each in a FRESH Word for Windows, PDF named like the docx.
3. python meas.py OUT/t-*.pdf  -> line 1's end and last 8 characters, line 2's first 8.
Read-out: a LONE "×" ending line 1 = Word breaks × | digit in that variant; "×1" always together = it does not.
