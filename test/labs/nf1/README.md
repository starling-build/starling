# Lab nf1 — where Word parts a nested table at a page foot

Source: lo-c7082c66 (nested table in a table cell, a centred floating table inside, page 595x842, margins 36.7pt).
Nine variants: the top and bottom cell margin of the outer row's cell and the middle cell (m0 / m113 / m300 twips)
x the floating table's last row least height (small 200 / orig 3392 / large 6000 twips).
Print each to PDF in Word for Windows. Report, per document and page: the baseline of the LAST text line on each
page, and the x/baseline of the first line of the next page (the text of the float, 'Table4 test' / 'document').
Why: our reserve at the foot for the part of a nested row that goes on is 2 cells' margin+line plus the outer top gap
plus a FITTED 3pt; one document (orig) fits it, any 1.1-7pt gives Word's page 3.
