# lenovo-5: survey of every Slides table page under 100 (round file 11:40Z), 2026-11-22

74 pages with "table" in FEATURES and score under 100. I rendered the 19 decks behind the worst pages and compared line positions with PowerPoint's print (matched by text, offset over 3 pt).
Result: almost no page is table geometry. Causes found:
- Chart labels, not tables: ce626c34 p5/p7/p9/p11 (table text matches PowerPoint to 0.1 pt; the loss is chart axis and category labels, 52 lines against 81), 99f6ddd1 p23 and p19 (percent axis, Japanese legend), e365f9b4 p17 (axis numbers), ko-c03ed80e p11/p24/p31 (Korean category labels drawn one character per line), LIBRE_OFFICE p2/p4/p6/p8 (chart data labels 3-6 pt off), ko-e114b968 p51/p57/p11 and likely p37/p68.
- Title box, not table: 2b078099 p3 (two-line title 14.5 pt too high).
- Text composition: ko-2fd3de28 p136 (Latin mid-word break, lenovo-3), 5a8cce85 p20 (Persian RTL pieces), ko-2ad6ce9d p4 and 5cf98ad4 p35 (EA line breaks inside table cells).
- Table geometry, one page: 99f6ddd1 p12 (Meiryo UI, 150%, fontAlgn ctr). All 24 pt text is 6.1 pt (0.254 em) high in ours, and the rows holding 36 pt symbols are shorter. amd-perf and lenovo-2 already hold it. My Meiryo UI entry (win ascent 2171, descent 430 of 2048) gives asc - desc = 0.850 em; amd-perf's fit needs 0.854, so that entry is right, and the missing piece is the "+ (m-1) x 1.2 em" above-baseline term they described. The symbols ◎ △ draw in MS PGothic in PowerPoint's print (lenovo-2's open question), which also explains the taller rows.
Table cell text positions are otherwise exact (0.1 pt) on every page I checked. No table-geometry PR from me comes out of this survey.
