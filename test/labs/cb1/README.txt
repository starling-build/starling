Lab cb1 -- where the paragraph mark of a column-break paragraph goes in Word for Windows (Linux lo5, 2026-11-01).
Background: LibreOffice's tdf165492 (compat 14, two columns, a table, then an empty paragraph holding only <w:br w:type="column"/>): Word's print
opens the NEXT column with an empty line (the break paragraph's mark), 28pt above the table; we put the table at the column top. We gave the mark
to the next column in compat < 15 for every column break in a document with columns -- and zh-6cd1befe (100 -> 97.5) and zh-8f9b19f4 (99.4 -> 92.3)
dropped: there Word shows NO such empty line. Their break paragraph follows TEXT (not a table) and carries a style with 5pt space before and a first-line
indent. Question: what decides it -- what precedes the break, the paragraph's properties, compat mode 14 vs 15, the column layout?
Each document = 8 pages, one section per page (nextPage), 2 columns (or 1), paragraph "AVn" (column 1), the break paragraph variant, then "BVn" (next column).
  V1 text then an empty paragraph with only the column break        V2 a 1-row table, then that empty break paragraph (tdf165492)
  V3 break paragraph: space before 5pt + first-line indent 840      V4 the break in the SAME paragraph as "AV4", nothing after it
  V5 break paragraph: exact 26pt line                               V6 break paragraph: 12pt space after
  V7 break paragraph centred with an 18pt run                       V8 text, empty break paragraph, then BV8 inside a table cell
Documents cb1-NN-mMODE-LAYOUT: MODE = compat 14 or 15; LAYOUT = two (2 equal columns), narrow (1272 + 7000 twips, as zh-6cd1befe), twogrid (two + docGrid lines 312), onecol (1 column: the break is then a page break; pages differ).
Fonts: Arial 12pt (Normal: no space after, single). Page A4, 1-inch margins.
usage: build.py OUTDIR regenerates docx/. Print each to PDF with Word for Windows, then: analyze.py PDF-or-DIR > table (TSV, one row per page).
Columns: doc, page, variant, A_top, B_top, B_left, dy = B_top - A_top. dy = 0 -> BVn is at the top of column 2 (no empty line); dy > 0 -> an empty line (the mark) stands first.
Our table (compat 14 with the mark in column 2, compat 15 without): CB1-OURS.tsv. Most useful: the m14 'two' and 'narrow' documents, then m15.
