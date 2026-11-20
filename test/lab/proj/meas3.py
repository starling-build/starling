#!/usr/bin/env python3
"""meas3.py proj3.pdf > PROJ3-TEXT.tsv: every word on every page with its box in page points (the chart's own
raster image box is in meas2.py's '#img' rows; pair the two by page)."""
import sys, pymupdf
d = pymupdf.open(sys.argv[1])
print('# page\tword\tx0\ty0\tx1\ty1 (page points)')
for pn, p in enumerate(d, 1):
    for w in p.get_text('words'):
        print('%d\t%s\t%.2f\t%.2f\t%.2f\t%.2f' % (pn, w[4], w[0], w[1], w[2], w[3]))
