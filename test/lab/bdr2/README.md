# bdr2: where a bordered paragraph's box goes when a break splits it

Word for Windows, Letter, margins 1in, compat 15. Print each .docx to PDF at its natural pagination (do not change anything).
Every document: a plain heading line "lead", then bordered paragraphs: 3pt single box (sz 24, space 4pt, all four sides); name = bdr2_<case><s|n><before>:
s = yellow shading FFFF99, n = no shading; before = space before 0 or 40pt.

- b1: one paragraph "AAA" <page break> "BBB" (the paragraph is split across two pages)
- b2: one paragraph that STARTS with a page break, then "BBB" (empty first fragment)
- b3: "AAA" <page break> ends the paragraph; next paragraph "CCC" has the identical border
- b4: two columns; one paragraph "AAA" <column break> "BBB"
- b5: three identical paragraphs AAA, BBB, CCC, after 10pt (shared box?)
- b6: two identical paragraphs with a red w:between line

Please measure, per page / column and fragment: the box outline (top, bottom, left, right y/x), the fill area, and the text baselines. What matters: does the box of the fragment after the break start at the text, or reach up over the space before; is the empty fragment line before a break drawn and filled; are side lines continuous across the space between joined paragraphs; where does the w:between line fall.
