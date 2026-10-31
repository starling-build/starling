Lab wr1 — why Word for Windows puts a line holding an over-wide inline rectangle on a page of its own. NOT for office.
Question (starling-bd, LibreOffice's tdf38575_fullWidthLine): Word's print has 4 pages: the title alone on page 1, the rectangle (476.65pt wide, 1.45pt high,
inline, in the SAME paragraph as the title, spacing line=0 atLeast; text width is 425.2pt) alone at the top of page 2, and every other paragraph from page 3.
Nothing breaks the page in the file. Ours puts it all on page 1 (2 pages).
Five documents, all made from that one by one change (docx/):
  A-control.docx         the original: Word must print the 4 pages above.
  B-narrow.docx          rectangle narrowed to 425pt (fits the line).
  C-normal-spacing.docx  the title paragraph's spacing line=0 atLeast removed.
  D-own-paragraph.docx   the rectangle in a paragraph of its own (same pPr), title in the one before.
  E-rect-only.docx       the title text removed: a paragraph with only the rectangle.
1. Print each in a FRESH Word for Windows, PDF named like the docx.
2. Read-out wanted per print: the page count, and for each page what is on it (title, the rectangle, "Turandot", the last text). In particular: is the
   rectangle on the same page as the title? Is the text after it on the rectangle's page or the next?
