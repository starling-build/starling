Lab col2flow (lenovo-5): zh-b5359de4 landscape->portrait variant. Last section is continuous, 2 columns,
starts near the bottom of a page. Paragraphs Q69..Q81 carry labels (Q77..Q81 are the empty section-start paragraphs).
Word's print (sect5359-portrait): the section's empties 80, 81 go to the NEXT page (95.3, 171.0, then the contents title at 247.0);
ours puts them in column 2 of the same page, so the title lands 152 pt too high.
Question: when does Word flow a continuous 2-column section's tail into column 2 on the same page vs the next page?
Docs: labels (as above), lastcols1 (last section 1 column), higher (4 empties before the break removed so the section starts higher).
Print: page, baseline, text for every line incl. empty ones (labels show which paragraph is which).
