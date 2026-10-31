Lab as13 — a paragraph of only a page break at the foot, with less than a line left (macOS-doc, 2026-10-31, T252).
Build: python3 build.py OUT. 12 documents: room left on page 1 R = 100 (control), 20, 10, 3 points x the block after
the break: floating (a one-row floating table, tblpY 1, then an ANCHOR paragraph), table (an ordinary table, then ANCHOR),
text (TEXT, then ANCHOR). All mode 15, Times New Roman 12 (single, 0 before/after); the filler is one paragraph of exact line
height. Print with Word for Windows to PDF and report, per document, the PAGE and y (PDF text top, pt) of FILL, TABLE (or TEXT)
and ANCHOR. Ours, for reference, is in AS13-OURS.txt.
