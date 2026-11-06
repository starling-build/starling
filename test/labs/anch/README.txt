Lab anch -- where does Word put an empty wrapNone box whose paragraph also holds a wrapping chart that pushes the paragraph's line below it? (Linux lenovo-5, 2026-11-06)
Background: lo-7b8ccfbe (base.docx): one paragraph, an empty text box (wrapNone, in front, 102x33pt, 6.4pt below the paragraph) and a wrapSquare chart (465x354pt, 9.0pt below).
Word keeps the box at the paragraph top (77.2 on a chart frame 79.9..434.2). In zh-d62da4dd (box 32.1, chart wrapTight and BEHIND text, 27.3) Word sets the box UNDER the chart. Ours moves the box with the pushed line in both.
Everything else is identical to base.docx; only these change (A1 is the original):
  A1 box 6.4 / chart 9.0 square front      A2 box 32.1 / 9.0 square front   A3 6.4 / 9.0 tight front        A4 32.1 / 9.0 tight front
  A5 6.4 / 9.0 square BEHIND               A6 32.1 / 9.0 square behind      A7 6.4 / 9.0 tight behind       A8 32.1 / 9.0 tight behind
  A9 box 32.1 / chart 60 square front (box above chart top)   A10 box 90 / chart 60 (box below)   A11 both at 0
usage: build.py OUTDIR regenerates docx/ (needs src/base.docx). Print each with Word for Windows as the corpus prints are made, then analyze.py PDF-or-DIR > ANCH-WORD.tsv
Columns: doc, top y of the box, top y and bottom y of the chart frame (points). What matters: is the box at the paragraph top + its offset, or under the chart (about chart bottom + offset)? Send the PDFs and ANCH-WORD.tsv on the branch.
