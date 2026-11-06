Lab hyph2 -- how much overflow does Word tolerate for a hyphen-ended Latin piece at the line end? (Linux lenovo-5, 2026-11-06)
Follow-up to lab hyph (whose 5.25pt steps cannot test a near miss). Target: zh-bfe04e2f p8, "S19-" over the margin by 6.29pt in mode 12; Word breaks before it.
Each document: A4, 1-inch margins, SimSun 10.5pt. 50 paragraphs, each a label line then 15 CJK chars (157.5pt), the piece, then a CJK tail that wraps.
The line width (right indent) is set so the room for the piece = width("S19-") + delta, delta = -3.00..+3.00 pt in 0.25pt steps. Tags: Hm075 = piece H, delta -0.75; Hp050 = +0.50.
  pieces: H "S19-" (CJK follows), A "S19-A"
  hyph2-1: compat 12, SimSun, left.  hyph2-2: compat 12, Times New Roman Latin (SimSun CJK), left.
  hyph2-3: compat 15, SimSun, left.  hyph2-4: compat 15, Times New Roman, left.  hyph2-5: compat 12, SimSun, justified.
Print with Word for Windows exactly as the corpus prints are made. Then: analyze.py PDF-or-DIR > HYPH2-WORD.tsv
Columns: doc, tag, first line's text, its last 6 characters. What matters: per doc and piece, the delta at which the first line stops ending before the piece.
usage: build.py OUTDIR regenerates docx/.
