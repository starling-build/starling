Row fit per book default font. 28 workbooks bk-<book>-<face><size>.xlsx: 40 identical rows of
"Row A1.." in one cell font, no ht, in a Verdana 10 or Arial 10 book (defaultRowHeight 12.75).
Print each to PDF (Excel for Windows, one page or more) and send back the row pitch
(median y gap between rows of the same column) per workbook, measured by position.
Why: Segoe UI 8 prints 14.52 in a Verdana 10 book but 14.88 in a Calibri 11 book (37 vs 39 screen px);
decides whether row px = hinted px + a per-book padding.
