Lab sqz3 (for `windows`, Word for Windows). Why does Word take or refuse a lone ideograph past half an em at a line end?
Run `python3 -I test/labs/sqz3/spec/gen.py test OUT`, open the 48 files in OUT in Word, print to PDF (same page setup as lab wsf), send the PDFs.
Each file has 43 paragraphs, W stepped 0.5 pt; the read-out is the first W at which the final 工 stays on the first line, per variant:
spaces 0/2/4 x justified/left x compat 14/15 x what follows 工 (ideograph / digit / "(" / "，").
Covers items 27083953 (对), 9e020c95 (于), 7b125a21 (word-gaps-tasks.md, squeeze one-offs, amd-3).
