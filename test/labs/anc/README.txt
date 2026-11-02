Lab anc (amd-3), for lo-eb12e7d4 p15: pictures anchored in a two-column section that a continuous one-column section follows. Word balances the two columns there (the last section starts under them), and the question is how a picture changes the balance and where it stands.
Page 420x300pt, margins 36/50. One page per variant (a one-column title line "X", then 12 one-line paragraphs "X-p1".."X-p12" in two 175pt columns, then the one-column paragraph "X-after" in a continuous section). The picture is a 40pt-wide red square (a 80x80 png), anchored in the paragraph named; x is from the column's left edge, y from the paragraph's top.
 A control (no picture): 12 lines
 B no wrap (wrapNone), 40x40 at (20,0) in p3
 C top-and-bottom, 40x40 at (20,0) in p3
 D square wrap, 40x40 at (20,0) in p3
 E inline 40x40 in p3
 F no wrap 40x40 at (20,0) in p12 (the last paragraph)
 G no wrap 40 wide x 100 high at (20,0) in p3
 H no wrap 40x40 at (100,0) in p3: straddles the column's text width? (column is 175pt wide: x 100..140, inside)
 I no wrap 40x40 at (20,150) in p3: 150pt under the line, below the whole balanced block
 J top-and-bottom 40 wide x 100 high at (20,0) in p3
Please print and report, per variant: the page, the y of X-p1 and of the last line of each column, which paragraph each column ends with, the y of X-after, and the picture's bounding box.
Questions: (1) does a picture with no wrap (B, F, G, H, I) change where the columns break (A vs B..)? (2) top-and-bottom (C, J) and square (D) in a column: does the text move, and does the balance count that room? (3) is an anchor in the second column (F) placed in the second column? (4) inline (E) vs A.
meas.py prints every text line of every page (python3 meas.py anc.pdf > ANC-WORD.tsv); the pictures' boxes need a look at the page.
