# Lab persp3 — tilted 3-D columns: Word's turn-70 labels, auto-height, and the same chart in PowerPoint and Excel

51 files in `docs/`, made by `gen3.py` (rerun to regenerate). Every chart is a 3-D clustered column chart, no title,
432 x 252 pt (5486400 x 3200400 EMU), perspective 30 unless noted. Default: rotX 30, rotY 40, 3 series, 4 categories
"Category n", legend on the right, both axes shown.

## What to print
Print every file with the program that owns it, one page each, at 4 px/pt as for lab persp. Push the PNGs (or a TSV of
each chart's drawn bounds) to `wip/lab-persp3-prints`, named after the file.

- `persp3-*.docx` Word for Windows. Chart is inline, left of the text column, first paragraph; page margins 90 pt left/right, 72 top.
- `persp3-F-*.pptx` PowerPoint. One slide, 680 x 453 pt; chart frame at (36, 36) pt, 432 x 252.
- `persp3-F-*.xlsx` Excel. Chart anchored at B2, 432 x 252 pt (one-cell anchor). Print the sheet to PDF/PNG; the chart is on page 1.

## Groups
- **L** (docx): the turn-70 question. Word keeps the box bottom at the room bottom at turn 70 with labels; ours shrinks ~20 pt.
  L-v30-70-* vary legend, label length, axes, category count; L-v15-60, v30-55/85/100 find where the drop starts.
- **S** (docx): box shape by series count (s1..s8), category count (c2..c8), stacked and percent-stacked; axes and legend deleted.
  S-s1-hp50 and S-s6-hp100 state a height percentage.
- **F** (docx + pptx + xlsx twins): the same 7 charts in all three programs. The chart area has a magenta 0.75 pt border so the
  frame is visible in every print. If the PowerPoint and Excel prints match Word's, our camera can serve Slides and Sheets too.
