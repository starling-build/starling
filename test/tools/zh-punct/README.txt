lenovo-5's line-end punctuation census tools (2026-11-01), for macOS-doc's squeeze question. Both read Word's prints (test/corpus/docx/word-win) against OUR PDFs
from a sweep dir (edit the O= path at the top: full-baseN/pdf from test/tools/docx-sweep.sh), PyMuPDF, ~100 s on 756.
 hangcount.py  per closing mark (” ’ 」 』 ） 》 〕 】): lines of Word ending in it that hang past the margin vs lines ending in it, and the same for ours.
 punct2.py     the same census for opening/closing marks at line starts/ends (what a line gives up).
Last result (tip of 2026-10-31, Windows mode): Word hang/ends vs ours -- 》 300/677 vs 320/632; 】 37/359 vs 42/359; 〕 27/55 vs 37/56; ’ 3/3 vs 1/3; 」 161/467 vs 156/465; 』 1/5 vs 0/5; ” 186/388 vs 301/447; ） 1616/5281 vs 1665/5287.
So hanging is clean for every mark but ” (Word hangs 48% of lines ending in ”, ours 67%); ” has no clean rule without a lab: origin/wip/lab-cq1 (test/labs/cq1) is that lab, built but NOT YET PRINTED by `windows` (no CQ1-WORD.tsv on the branch).
