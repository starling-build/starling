bug66675 with one change to row 12 each (Excel prints row 12 at 15.24 pt in the original; we print 14.52).
a unmerge A12:D12; b unmerge E12:G12; c vertical=center; d drop H12/I12; e no ht attr; f wrap off; g original.
Print each to PDF (same as the corpus), report row 12's height (horizontal rules around the "Nomination Point Name" row, page 1).
h-l: row 12 reduced to one cell group (h only A12, i only E12, j only H12, k only the empty styled cells, l none); merges A12:D12/E12:G12 removed. Report row 12 height each.
