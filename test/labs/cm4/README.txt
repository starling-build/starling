Lab cm4 (amd-3), for zh-5450d509 p6 / zh-785e46f8: a vertically centred cell merged over THREE rows (vMerge restart + 2 continue), the page foot falling at a row boundary or inside a row. Plus a plain row after the span.
Page 420x300pt, 200pt of text: a title line (the table's tag) and 12 table lines of 14.65pt per page. Each table starts on a new page (pageBreakBefore on the tag line).
Columns: A = the merged cell (one line "<tag>-K", centred), B = one line per row ("<tag>-b1..b3", centred), C = a centred cell with n paragraphs per row ("<tag>-r<row>-<k>").
Tables (lead plain row lines; lines of rows 1,2,3 of the span):
 A (5,5,5)  rows 1-2 = 10 lines, the foot inside row 3
 B (6,6,3)  rows 1-2 = 12 lines: the foot exactly at the boundary after row 2
 C (4,10,4) the foot inside row 2
 D (3,9,5)  rows 1-2 = 12 lines: boundary after row 2
 E lead 2 + (4,4,6)  the span starts under a plain row of 2 lines; the foot inside row 3
 F (3,3,3)  control, all on one page
 G (2,2,12) the foot far inside row 3
 H (8,3,6)  rows 1-2 = 11 lines, the foot after 1 line of row 3
 I (5,5,5), J (6,6,3): as A and B but every cell is ONE line and the rows' heights are set by trHeight (atLeast, n x 14.65pt): rows can't part, they move whole.
Please print and report, per table: the page and baseline y of the K line (and which page of the span it is on), the y of every b line, the right-hand lines at each page's foot and head, and where the rules end on each page.
Questions: (1) at a boundary after row 2 (B, D) is K centred over rows 1-2 only (the part on that page) or over the whole span, and on which page does it print? (2) where the foot is inside row 3 (A, E, G, H): centred in the first page's part, or the whole span's centre, or does it jump? (3) inside row 2 (C)? (4) do I/J (rows that cannot part) differ from A/B?
meas.py prints every text line of every page (python3 meas.py cm4.pdf > CM4-WORD.tsv).
