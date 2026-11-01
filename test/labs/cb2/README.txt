Lab cb2 -- the paragraph AFTER a column-break paragraph (Linux lo5, 2026-11-01). Follow-up to lab cb1 (wip/lab-cb1, CB1-WORD.tsv).
Background: cb1 says Word puts the break paragraph's mark at the top of the NEXT column (dy > 0 for an ordinary B paragraph). But two real documents (zh-6cd1befe, zh-8f9b19f4) show NO such line:
in zh-6cd1befe the paragraph after the break is a HEADING with 12pt space before (spacing before=240 beforeLines=100) in 22pt type, and Word's heading stands exactly where ours stands when we do NOT
give the mark a line (when we do, it is 26pt too low = a 13.8pt mark line + the heading's 12pt before). In zh-8f9b19f4 the break paragraph has a 1pt font and a 0.7pt auto line (spacing line=14 auto, sz 2).
cb1's B paragraph never had space before. Hypothesis to test: the mark line is there, but the following paragraph's space before is dropped (or the line is not there when B has space before).
Each document = 8 pages, one section per page (nextPage), 2 columns 1272 + 7000 twips (narrow, as zh-6cd1befe), paragraph "AWn" (column 1), the break paragraph, then "BWn" (next column). Arial 12pt, A4, 1-inch margins.
  W1 text, empty break paragraph; B has 12pt space before, 22pt type          W2 break paragraph with 5pt before + first-line indent 840 (cb1's V3); B 12pt before, 22pt
  W3 as W2, B also states beforeLines=100                                     W4 CONTROL: as cb1's V1, B plain 12pt, no space before
  W5 break paragraph 1pt font, 0.7pt auto line (zh-8f9b19f4); B 4.9pt before  W6 as W5; B plain, no space before
  W7 A is an exact 26pt line, V1 break paragraph; B 12pt before, 22pt         W8 text and break in ONE paragraph; B 12pt before, 22pt
Documents cb2-NN-mMODE-LAYOUT: MODE 14 or 15; LAYOUT narrow, or narrowgrid286 (the same plus <w:docGrid w:linePitch="286"/> with no type, as zh-6cd1befe).
usage: build.py OUTDIR regenerates docx/. Print each with Word for Windows, then analyze.py PDF-or-DIR > table. Columns: doc, page, variant, A_top, B_top, B_left, dy = B_top - A_top.
What matters: dy for W1-W3, W5, W7, W8 against the controls W4 and W6 (the same without space before): is dy(W1) = dy(W4) + 12 (+ the type difference), or smaller?  Our table: CB2-OURS.tsv (compat 14 without a mark line; no mark rule on the tip).
