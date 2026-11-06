Lab brk1 (for `windows`, Word for Windows; owner amd-5). What does Word do with the blank before an opening bracket, mid-line and near the line end?
Run `python3 -I test/labs/brk1/spec/gen.py test OUT`, open the 32 files in OUT in Word, print each to PDF (same page setup as lab wsf), send the PDFs.
Each file has 56 paragraphs, line width stepped 0.5 pt. Variants: bracket （ 【 《 「 x jc both|left x compat 14|15 x 0|1 space before the second bracket.
Covers zh-de97afa7, zh-40fe33a3, zh-9e020c95 (word-gaps-tasks.md).
