#!/usr/bin/env python3
"""analyze2.py bar3d.pdf > bar3d2.tsv : per page the chart frame (largest rectangle drawn),
the back wall's gridline rows (y, x0, x1) that span at least 85% of the topmost one, and every
number label (right edge, top) left of the wall. Needs PyMuPDF and numpy."""
import sys, pymupdf as f, numpy as np
S = 4
for n, pg in enumerate(f.open(sys.argv[1]), 1):
    fr = max((d['rect'] for d in pg.get_drawings()), key=lambda r: r.width * r.height, default=f.Rect(0, 0, 0, 0))
    pm = pg.get_pixmap(matrix=f.Matrix(S, S))
    a = np.frombuffer(pm.samples, np.uint8).reshape(pm.height, pm.width, 3).astype(int)
    g = (abs(a[:, :, 0] - a[:, :, 1]) < 8) & (a[:, :, 0] < 215) & (a[:, :, 0] > 100)
    rows = []
    for y in range(pm.height):
        xs = np.where(g[y])[0]
        if len(xs) > 100 * S: rows.append((y / S, xs.min() / S, xs.max() / S))
    top = rows[0] if rows else None
    wall = [r for r in rows if top and (r[2] - r[1]) >= 0.85 * (top[2] - top[1])]
    labs = [(w[4], round(w[2], 1), round(w[1], 1), round(w[3], 1)) for w in pg.get_text('words') if w[4].replace(',', '').isdigit()]
    print('page', n, 'frame', '%.1f,%.1f,%.1f,%.1f' % tuple(fr), 'wall', ';'.join('%.1f,%.1f,%.1f' % r for r in wall),
          'nums', ';'.join('%s,%s,%s,%s' % l for l in labs), sep='\t')
