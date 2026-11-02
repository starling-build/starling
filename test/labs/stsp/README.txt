Lab stsp -- does w:suppressTopSpacing (compat setting) raise the FIRST line of a page when its lines are exact-height? (Linux lo5, 2026-11-02)
Background: LibreOffice's tdf161139_orrick-org-min3 (lo-5a97a8ea) has suppressTopSpacing in its compat and a body of exact 24pt lines in 12pt text. Word's print puts the first body baseline
9.5pt HIGHER than ours (76.0 vs 85.5) while later lines match. Guess: the first line is raised by (exact - natural line height) * 0.8 = (24-14)*... — one witness, formula unconfirmed.
Every document: Letter, 1in margins, Times, four paragraphs "BODY LINE n" (no spacing after), compat 15. Names: E<exact>s<size>-on/-off = exact line height in pt, font size pt, suppressTopSpacing on/off.
 E24s12 E18s12 E30s12 E36s12 (heights), E24s10 E24s14 (sizes), E12s12 (exact = size), -sb12 = 12pt space before the first paragraph, AUTO12 = automatic line height.
usage: build.py OUTDIR regenerates docx/. Print each with Word for Windows exactly as the corpus prints are made, then analyze.py PDF-or-DIR > table. Send the table on the branch (STSP-WORD.tsv).
What matters: line1_top of every -on against its -off twin (the raise, if any), as a function of exact height and size; whether lines 2-4 move too.
