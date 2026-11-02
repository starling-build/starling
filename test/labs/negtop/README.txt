Lab negtop -- where does Word put the BODY when the page's top margin is NEGATIVE (Word reads it as "exact") and the header needs more room? (Linux lo5, 2026-11-02)
Background: LibreOffice's tdf161139_orrick-org-min3 (lo-5a97a8ea) has w:pgMar top=-1327 (66.35pt), header=431 (21.55pt), and a header holding one exact-height table row 744pt tall
whose paragraph has 36pt space before. In word-win's print the body's first line stands on the SAME baseline as the header's first line (the numbers 1-28 in the header line up with the
body lines): both at 21.55+36 = 57.55 line top, NOT at the 66.35 the margin says. Ours (with exact margins now implemented) puts the body at 66.35, 8.8pt low, and every line misses.
Question: what rule puts the body at 57.55? Candidates: body starts at the header's first paragraph (header top + its space before); at (header distance + space before) whatever the margin says;
at |margin| minus something; only when the header is a tall table.
Each document = Letter, 1in side/bottom margins, Times 12, compat 15, five body paragraphs "BODY LINE n" (exact 24pt lines, no spacing), a header "HEADER LINE" (exact 24pt) in the form named below.
  N1 control top +1327, short header (space before 36pt)     N2 top -1327, same short header            N3 top -1327, header space before 0
  N4 top -1327, no header at all                              N5 top -1327, tall exact-row header (744pt), space before 36pt
  N6 control top +1327, tall exact-row header                 N7 top -1327, short header, header distance 0
  N8 top -600, short header                                   N9 top -1327, tall header, space before 0   N10 top -1327, tall header, header distance 1440
usage: build.py OUTDIR regenerates docx/. Print each with Word for Windows exactly as the corpus prints are made (no markup in these), then analyze.py PDF-or-DIR > table.
Columns: doc, header_top, body1_top (tops of the text boxes on page 1), body lines on page 1, pages. Send the PDFs' table on the branch (NEGTOP-WORD.tsv).
What matters: body1_top for N2..N10 against N1 (66.35 + line) and against header_top.
