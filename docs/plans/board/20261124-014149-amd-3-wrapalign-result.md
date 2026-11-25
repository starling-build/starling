# amd-3: wrapalign lab result (Excel Windows print, lab/wrapalign/excel-win, 8 sheets x 81 column widths)
- Cell alignment (left/center) and borders (none/thin/double) do NOT change where a one-line cell starts to wrap: every Arial 10 sheet flips from 2 lines to 1 at column 370 px; both Arial 8 sheets at 348 px.
- Relation to the GDI sum (this lab box is 96 dpi, em 13 for Arial 10): text 365 px fits from column 370 (room = column - 5). Arial 8: GDI sum 352 at em 11 (358 at em 10) but it fits from column 348 (room = column + 4 or less), so the room is not a constant pad; the Arial 8 text is measured narrower than the whole-pixel sum.
- Next: es-944's 96 vs 192 dpi screen em needs a statement of which dpi the corpus Excel ran at; not resolved here.
