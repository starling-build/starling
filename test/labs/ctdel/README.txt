Lab ctdel -- why does Word set LibreOffice's CT-formatted-deletion "Deleted:" balloon 8pt (scaled) right of ours and narrower? (Linux lo5, 2026-11-01)
Background: in word-win's print of CT-formatted-deletion (three tracked-deleted paragraphs, the first in the Quote style with a pPrChange), the balloon text starts at x 430 and
wraps at x 567 (line 1 ends "...Maurisetorci" earlier than ours), where ours starts at x 422 and wraps at 584. In all 18 other prints with "Deleted:" balloons ours and Word's start together.
Suspects: the deleted paragraph's own indents (Quote = 864 twips each side), centring, italic, the pPrChange, or the kept/deleted mark.
Each document = A4, 1-inch margins, Arial 12, compat 15, trackRevisions on; paragraph "Before Dn", ONE tracked-deleted paragraph (text and, unless said, mark), paragraph "After Dn".
  D1 control: Normal paragraph deleted                          D2 Quote style (ind 864/864, centred, italic) deleted
  D3 Quote + pPrChange (the original's shape)                   D4 Normal + direct indents 864/864        D5 Normal + centred
  D6 Normal + italic runs                                       D7 Normal + pPrChange                     D8 Normal + left 864 only
  D9 Normal + right 864 only                                    D10 Quote, text deleted, mark KEPT        D11 Quote paragraph VISIBLE with one deleted run inside
  D12 Normal + first-line indent 6pt
usage: build.py OUTDIR regenerates docx/. Print each with Word for Windows exactly as the corpus prints are made (All Markup, balloons on, the default "print markup"), then
analyze.py PDF-or-DIR > table. Columns: doc, number of balloon lines, left x of the balloon text, widest right x, first line.
What matters: left_x and right_x_max of D2..D12 against D1; and which of them reproduces the 8pt shift and the narrower wrap. Send the PDFs and the table on the branch (CTDEL-WORD.tsv).
