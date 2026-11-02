Lab ef (amd-3), for lo-eb12e7d4 p14: an inline picture on a line of 1.5 spacing, then an EMPTY paragraph of 1.5 spacing, then "TAIL", at the foot of a column.
Page 420x300pt, margins 50 top/bottom; text Times New Roman 10pt (line 11.5; at 1.5 spacing 17.25). Files: ef2.docx (two columns) and ef1.docx (one column).
Each page k (11 pages): tag line "Tk h=H", 8 one-line paragraphs, a paragraph holding only a 40pt-wide picture of height H (64..84 step 2), an empty paragraph, "Tk-TAIL", 3 more lines.
The picture's line is H + 5.75 high, so the room left under it for the empty paragraph (17.25) shrinks as H grows. Foot is at y 250.
Question: for each H, is the empty paragraph in the first column (TAIL right under it, same column) or does it start the next column (TAIL then 17.25 lower than the column top)?
 What is the room needed? Report per page: y_top of TAIL and its x0, the picture's bounding box if it can be read (else leave it).
meas.py prints every text line of every page (python3 meas.py ef2.pdf > EF2-WORD.tsv, and ef1.pdf > EF1-WORD.tsv).
