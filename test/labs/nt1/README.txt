Lab nt1 — where Word cuts a table nested in a one-row outer table at the page's foot (Linux lo5, 2026-10-30).
Background: LibreOffice's fdo77887 and fdo48718-1 are a 1-row outer table (trHeight atLeast 450pt, vAlign center) holding a
76-row nested table of 9pt rows (0.5pt borders, every paragraph with the same page-anchored framePr). Word's print sets 44 rows
on page 1; the last (row 44) has its text top at 878 on a 936.12pt page with a 70.9pt bottom margin, so it ends ~25pt (two rows)
BELOW the margin. Ours stops at 42 (row 43 would end at 876). Question: what limit does Word cut a nested table's rows by?
Candidates: (a) row heights without the border lines add up (12.26pt a row, not 12.76); (b) the footer distance (page - 35.45),
not the bottom margin; (c) the framePr; (d) the outer row's minimum height / vertical centring.
Build: python3 build.py OUT (7 docx; page 12242 x 18722, margins 1418/1701, compat 14, Arial 9pt single, 90 rows R01..R90).
Variants: b05 / b00 / b30 (nested row borders 0.5pt / none / 3pt); b05-short (outer row without the 450pt minimum);
b05-top (outer cell vAlign top); b05-frame (every nested paragraph carries the LibreOffice documents' framePr);
flat-b05 (the same 90 rows as a plain top-level table).
Report per document, from Word for Windows' PDF: the LAST row on page 1 (text and y, PDF text top, pt), the y of R01, and the
page count. Ours, for reference, in NT1-OURS.txt.
