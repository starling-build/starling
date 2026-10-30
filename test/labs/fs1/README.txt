Lab fs1 — float stacking (macOS-doc, 2026-10-31, T252).
Question: Word sets "Outer table 2" (a floating table, tblOverlap never, tblpY -2) 115.3pt under "Table 1"'s text
(Table 1: a floating table, one row of 91.5pt, tblpY -67), where ours sets it 92.5pt under: ~23pt more in Word.
Also floattable-outer-nonsplit-inner: the paragraphs after a table holding an inner floating table stand ~19.8pt lower.
Build: python3 build.py <path to sw/qa/writerfilter/ooxml/data/floattable-tables-lost.docx> OUT   (the file is in
test/corpus/docx/lo/docs/lo-22a53e2b229752d3.docx).
Print each with Word for Windows to PDF; report the y (PDF text top, pt) of "Table 1", "Outer table 2", "Inner table 2".
Variants: v0 original; v1 no inner table; v2 inner table not floating; v3 no Table 1; v4 Table 2 tblpY 500 twips;
v5 Table 1 row 50pt; v6 no inner + Table 2 row 30pt; v7 Table 1 not floating.
Round 2 (v8-v14): Table 1 tblpY 0, -400, +400; the paragraph after the tables in 24pt; Table 1 with a second row; Table 2 without tblOverlap never; (v14 = v0).
