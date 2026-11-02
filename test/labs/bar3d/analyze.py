#!/usr/bin/env python3
"""analyze.py bar3d.pdf > bar3d.tsv : per page, the back wall's gridlines (x0, x1, y) read from pixels,
the value labels' right edge and the category names' top. Needs PyMuPDF and numpy."""
import sys, pymupdf as f, numpy as np
S = 4
for n, pg in enumerate(f.open(sys.argv[1]), 1):
    pm = pg.get_pixmap(matrix=f.Matrix(S, S))
    a = np.frombuffer(pm.samples, np.uint8).reshape(pm.height, pm.width, 3).astype(int)
    g = (abs(a[:, :, 0] - a[:, :, 1]) < 8) & (a[:, :, 0] < 215) & (a[:, :, 0] > 100)
    rows = []
    for y in range(pm.height):
        xs = np.where(g[y])[0]
        if len(xs) > 100 * S: rows.append((y / S, xs.min() / S, xs.max() / S))
    words = pg.get_text('words')
    lab = [w for w in words if w[4].replace(',', '').isdigit() and w[0] < 150]
    print('page', n, 'rows', ';'.join('%.1f,%.1f,%.1f' % r for r in rows),
          'valueLabelRight', max([w[2] for w in lab], default=0), 'words', ' '.join(w[4] for w in words[:2]), sep='\t')
