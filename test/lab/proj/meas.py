#!/usr/bin/env python3
"""meas.py proj.pdf > PROJ-WORD.tsv: every straight black stroke segment inside each page's chart frame
(the box's outline), in points from the frame's top left. Columns: page, x0, y0, x1, y1, width."""
import sys, pymupdf
FX, FY = 72.0, 72.0
d = pymupdf.open(sys.argv[1])
print('# page\tx0\ty0\tx1\ty1\tstroke_width (frame pt from its top left; frame 400 x 300)')
for pn, p in enumerate(d, 1):
    for dr in p.get_drawings():
        col = dr.get('color')
        if col is None or max(col) > 0.2:
            continue
        for it in dr['items']:
            if it[0] == 'l':
                a, b = it[1], it[2]
                print('%d\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f' % (pn, a.x - FX, a.y - FY, b.x - FX, b.y - FY, dr.get('width') or 0))
            elif it[0] == 're':
                r = it[1]
                for (x0, y0, x1, y1) in ((r.x0, r.y0, r.x1, r.y0), (r.x1, r.y0, r.x1, r.y1), (r.x1, r.y1, r.x0, r.y1), (r.x0, r.y1, r.x0, r.y0)):
                    print('%d\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f' % (pn, x0 - FX, y0 - FY, x1 - FX, y1 - FY, dr.get('width') or 0))
            elif it[0] == 'qu':
                q = it[1]
                pts = [q.ul, q.ur, q.lr, q.ll, q.ul]
                for a, b in zip(pts, pts[1:]):
                    print('%d\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f' % (pn, a.x - FX, a.y - FY, b.x - FX, b.y - FY, dr.get('width') or 0))
