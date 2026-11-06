Lab hyph -- where does Word break a line at a hyphenated Latin piece ("S19-A") at the line end? (Linux lenovo-5, 2026-11-06)
Background: zh-bfe04e2f p8 (mode 12, no grid): the piece "S19-" fits the line by 11.8pt but needs 13.1 and marks give 12.2. Ours takes it onto the line, Word breaks before it.
Word DOES break after a hyphen before a letter elsewhere (NB-|IOT, FV3-|GFS), and takes some Latin pieces that overflow. We need the rule.
Each document: A4, 1-inch margins, compatibility mode 12, no grid, SimSun 10.5pt, text width 210pt (20 CJK chars) via a right indent. 50 paragraphs, each a small label line then:
  n CJK chars (15..19), m half-width digits "1" (0 or 1), the piece, then CJK tail that wraps. Room left for the piece = (20-n)*10.5 - m*5.25 pt.
  pieces: A "S19-A"  D "S19-1"  C "S19-中"  H "S19-" (CJK follows in the tail)  N "S19A" (control, no hyphen)
  hyph-1: SimSun both, left aligned.  hyph-2: justified.  hyph-3: Times New Roman for Latin, SimSun for CJK, left aligned.
Print with Word for Windows exactly as the corpus prints are made (default markup). Then: analyze.py PDF-or-DIR > HYPH-WORD.tsv
Columns: doc, tag (piece-n-m), the first line's text, its last 6 characters.
What matters: for each piece and room, whether the first line ends before the piece, inside it (after the hyphen), or after it. Send the PDFs and HYPH-WORD.tsv on the branch.
usage: build.py OUTDIR regenerates docx/.
