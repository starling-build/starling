Lab gq3 -- which element of zh-9c162f26's REAL lines makes Word refuse a squeeze (Mac 7bd18d8e, 2026-11-01). gq and gq2 printed identical to ours, so this uses the real
paragraphs A ('4、装饰装修期间每3日巡查1 次现场，发现…违规行为的，应立即…') and B ('…每日巡查1 次…') in the corpus package's one-cell table (371.55pt), jc both, with ONE element
changed per variant (see build.py's docstring): no '4、', '四、', no digits, no '3', no '1 ', no blank, no marks, no first '、', left aligned; R 0..8pt by 1pt.
Word's print of the original document: A line 1 ends '…行为的，' (43 characters not counting the blank), the '应' goes down; B ends '…的，应'. Ours (GQ3-OURS.tsv) takes '应' on A at R=0.
Print docx/gq3.docx (108 pages) with Word for Windows, `analyze.py gq3.pdf > gq3.tsv` (PyMuPDF, reads gq3-index.tsv), send the rows.
The variant whose count at R=0 differs from A-orig's, or whose drop moves, is the element.
