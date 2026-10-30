Lab sqz4 — which variable makes Word for Windows break between "×" and a digit? NOT for office.
Lab sqz3 (line G of zh-6b242483: "…9（家）|×1（每年1次", mode 14, FangSong 16pt, zh-CN) showed Word never leaves the "×" alone:
refused at -100 twips although the "×" fits unsqueezed (room 16.02, sign 15.96), taken at -120 as "×1" with the marks giving 7.2pt.
The corpus's Traditional cells (PMingLiU, zh-TW) do break "…）×" | "100%". Language and face move together there, so which one is the key is open.
Four variants (a as is; b language zh-TW in styles, themeFontLang and the run, face unchanged; c face PMingLiU, language unchanged; d both)
x four right margins (0, -60, -120, -200 twips = 11, 14, 17, 21pt of room for the lone "×") = 16 prints.
1. python build_h.py REPO OUT     (REPO = a checkout with test/corpus/docx/docs; build_g.py beside it)
2. Print each in a FRESH Word for Windows, PDF named like the docx.
3. python meas.py OUT/t-*.pdf  -> line 1's end and last 8 characters, line 2's first 8.
Read-out: a LONE "×" ending line 1 ("…）×" | "1（每年") = Word breaks × | digit in that variant. "×1" always together = it does not.
The variable (b alone, c alone, d only) that breaks is the key for the rule `timesDigit` (RichLayout._breaksBetween).
