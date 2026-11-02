LAB bar3d (for `windows`): the plot rectangle Word gives a 3-D clustered column chart whose plot layout is left to Word.
bar3d.docx: 13 pages, one chart each, a caption line above (v01 ... v13). Template = zh-b8de3ae2's chart 1 (rotX 15, rotY 20,
rAngAx 1, no plot layout, no wall lines). Varies: frame size F1/F3/F5 (b8de3ae2's charts 1, 3, 5), title on/off,
category names short/long, value maximum 9 / 99 / 9999.
Please: open docx/bar3d.docx in Word for Windows, print to PDF (keep the chart's own sizes, no scaling), save as bar3d.pdf,
run `python3 analyze.py bar3d.pdf > bar3d.tsv` and commit bar3d.pdf and bar3d.tsv to this branch (wip/lab-bar3d).
Charts have no linked workbook (their caches carry the data): if Word asks about links, say no.

SET B (docx/bar3d-b.docx, 14 pages, same procedure; run analyze2.py on its PDF -> bar3d-b2.tsv): the legend at right / top / none
(frames F1, F3), the narrow frames' category-name wrapping (F5, N4 = 400x300pt, N3 = 300x250pt, with short / long names).
