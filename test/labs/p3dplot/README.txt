Lab p3dplot — Word for Windows' auto plot box for a 3-D pie (zh-27a874b7, zh-d62da4dd). NOT for office.
1. python build.py test/corpus/docx/docs/zh-27a874b7*.docx OUT   -> 14 t-A*.docx (chart 1, page 3, varied; chart 2 a control)
2. Print each in a FRESH Word for Windows (quit between, none open), PDF named t-A*.pdf.
3. python meas.py OUT/t-*.pdf  (needs pymupdf + PIL) -> per print: chart 1's and chart 2's pie top/bottom/left/right/centre.
Send back the meas.py output and the PDFs.
