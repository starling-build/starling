#!/usr/bin/env python3
"""meas.py DIR > NB-WORD.tsv: per nb-*-orig.pdf page: every horizontal rule (height<1.6, width>100) of the lowest 6 distinct y with colour (purple = outer table's 800080), plus page count; and the vertical rules' lowest end per colour.
gap_purple_minus_black = lowest purple rule y - lowest non-purple rule y."""
import sys, os, re, pymupdf
print('# doc\tpage\tkind\ty\tx0\tx1\tcolour')
def col(c): return 'purple' if c and abs(c[0] - .5) < .05 and c[1] < .05 and abs(c[2] - .5) < .05 else ('black' if c and max(c) < .2 else str(c))
for f in sorted([x for x in os.listdir(sys.argv[1]) if x.endswith('-orig.pdf')]):
    name = f.replace('-orig.pdf', '')
    for pn, p in enumerate(pymupdf.open(os.path.join(sys.argv[1], f)), 1):
        hs = {}; vs = {}
        for d in p.get_drawings():
            r = d['rect']; c = col(d.get('fill') or d.get('color'))
            if r.height < 1.6 and r.width > 100: hs[(round((r.y0 + r.y1) / 2, 2), round(r.x0, 1), round(r.x1, 1), c)] = 1
            elif r.width < 1.6 and r.height > 20: vs[(c, round(r.y1, 2))] = 1
        for y, x0, x1, c in sorted(hs, reverse=True)[:8]: print('%s\t%d\thrule\t%.2f\t%.1f\t%.1f\t%s' % (name, pn, y, x0, x1, c))
        for c in ('purple', 'black'):
            ys = [y for cc, y in vs if cc == c]
            if ys: print('%s\t%d\tvmax\t%.2f\t\t\t%s' % (name, pn, max(ys), c))
