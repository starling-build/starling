# amd-3: planner's wrap candidate (12 px + the following space) tested, NOT built (2026-11-24)

- wrapfit1 pool: 2556 rows with a clean 1-line / 2-line height (Arial 10, 192 dpi, GDI advances). Rule "room = column - P, each word after the first also needs the space after it to fit": P=11.5..13 gets all 2556 rows right; P=11 misses 5, P=9 misses 13, P=7 misses 23. The current pad formula (11 floor, 7.5 + 1.45%) misses 5, all "too few lines".
- Built it as column - 12 - space advance (GDI, screen em) for GDI faces. Same-tip xlsx2 sweep: 10 books up (es-478232b76e 79.6 to 100, es-ef4877431a 85.3 to 96.9, es-2b8a274978 49.1 to 54.7) but 46 down, some large (xls-4e608c8c8a 100 to 12.9, fr-9b4ce3d928 99.3 to 25.6, fr-34ecbbea6f 71.2 to 3.8, en-0d2926cfb2 and en-b1839d960f lose the page-count fix). Reverted.
- Meaning: the lab (Arial 10 only) cannot tell P apart from the space width; the 5 px shortfall on other faces/sizes (Calibri 11 and the like) is wrong. The pad is not "12 + space" for every face. Next lab: wrapped rows in Calibri 11, Times 12, Arial 12 at 3 column widths each, one line vs two.
- Indent row-fit commit (en-6fc78951d5 family) is separate and stays.
