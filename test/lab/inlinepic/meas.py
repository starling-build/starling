#!/usr/bin/env python3
"""meas.py DIR > INLINEPIC-WORD.tsv: per doc and page, every inline picture's box (top, bottom) and the gap to the previous one on the page."""
import sys, os, glob, pymupdf
print('# doc\tpage\tk\ttop\tbottom\theight\tgap_from_prev')
for f in sorted(glob.glob(os.path.join(sys.argv[1], '*-orig.pdf'))):
    d = pymupdf.open(f); k = os.path.basename(f)[:-9]
    for pg in d:
        prev = None
        for i, im in enumerate(sorted(pg.get_image_info(), key=lambda m: m['bbox'][1])):
            b = im['bbox']; print('%s\t%d\t%d\t%.2f\t%.2f\t%.2f\t%s' % (k, pg.number + 1, i, b[1], b[3], b[3] - b[1], '%.2f' % (b[1] - prev) if prev is not None else '')); prev = b[3]
