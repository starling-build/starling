Lab b88: lo-88b29958 (LibreOffice tdf164500), landscape page 595x419, margins 72. Normal = Liberation Sans 36pt, spacing after 10, line 1.15.
Order in the file: frame paragraph "Initiating Coverage" (page-anchored), a floating table (tblpY 576 twips = 28.8pt, vertAnchor text, tblpX 7523 from the page),
then the ANCHOR paragraph (empty, holds a wrapSquare logo at paragraph offset -889000 EMU = -70pt, 46.7pt tall), then the text paragraph "Easier net order comps and an acceleration in pricing power;".
In Word's print of the original: the table's first text baseline is 119.5; the empty anchor line's span top is 96.7 (baseline ~129.4); the text paragraph's first baseline is 187.0 (57.6 under the anchor line = 47.6 + 10 after).
Our flow puts the anchor paragraph at the top margin (72), so its text would stand at baseline 168.7 without the table. Question: what puts Word's anchor LINE ~18pt under the top of the flow?
Per file, please send: the table's first text baseline, the anchor line (if there is any text, its baseline; else the span top of the empty line), the text paragraph's first baseline, and the logo's y.
b_orig: the original (check we read it as before).
b_noframe: without the "Initiating Coverage" frame paragraph.
b_notable: without the table.
b_nologo: without the logo.
b_text: the anchor paragraph holds the letter X before the logo.
b_before0: the anchor paragraph has spacing before 0, after 0, single line.
b_margin / b_page: the table's vertAnchor margin / page (tblpY the same 28.8pt).
b_offset0: the logo's paragraph offset 0 instead of -70pt.
