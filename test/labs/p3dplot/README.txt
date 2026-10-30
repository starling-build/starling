Lab p3dplot — Word for Windows' auto plot box for a 3-D pie (zh-27a874b7, zh-d62da4dd). NOT for office.
1. python build.py test/corpus/docx/docs/zh-27a874b7*.docx OUT   -> 14 t-A*.docx (chart 1, page 3, varied; chart 2 a control)
2. Print each in a FRESH Word for Windows (quit between, none open), PDF named t-A*.pdf.
3. python meas.py OUT/t-*.pdf  (needs pymupdf + PIL) -> per print: chart 1's and chart 2's pie top/bottom/left/right/centre.
Send back the meas.py output and the PDFs.

Lab p3dplot2 — the same chart sized by its labels: python build2.py test/corpus/docx/docs/zh-27a874b7*.docx OUT2
-> 14 t-B*.docx (chart 1's moves removed, then one thing varied: which labels show, name length, dLblPos, parts shown,
separator). Print each in a fresh Word for Windows as before; send `python meas.py OUT2/t-*.pdf` and the PDFs.
(build.py: the f-string fix from windows' run folded in.)

Lab p3dplot3 — where Word sets a 3-D pie's inside (best-fit) labels as the pie turns:
python build3.py test/corpus/docx/docs/zh-27a874b7*.docx OUT3 -> 12 t-C000..t-C330.docx (chart 1, moves removed, rotY in
30-degree steps). Print each in a fresh Word for Windows; send `python measl.py OUT3/t-*.pdf` (each label's box centre and
the pie's extent) and the PDFs. (meas.py now importable; same output.)
