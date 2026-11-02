#!/usr/bin/env python3
"""meas.py PDF > PIEOUT-WORD.tsv: per page (variant order as gen.py's VARIANTS), the disc's outline in points from the
page's top-left: left, right (widest coloured row), and down the middle column: top (far edge of the top face), near
(where the rim's darker colour starts), bottom (the rim's foot). Coloured = not grey (max-min channel > 30) at 4 px/pt."""
import sys, pymupdf, numpy as np
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from gen import VARIANTS
Z = 4
print('# page\trotX\tpersp\tdepth\th\tleft\tright\ttop\tnear\tbottom\ttop_rgb\trim_rgb')
for i, p in enumerate(pymupdf.open(sys.argv[1])):
    pm = p.get_pixmap(matrix=pymupdf.Matrix(Z, Z), alpha=False)
    a = np.frombuffer(pm.samples, dtype=np.uint8).reshape(pm.height, pm.width, 3).astype(int)
    col = (a.max(2) - a.min(2)) > 30
    ys, xs = np.nonzero(col)
    if len(xs) == 0: print('%d\tNONE' % (i + 1)); continue
    rows = {}
    for y in np.unique(ys):
        xx = xs[ys == y]; rows[y] = (xx.min(), xx.max())
    wy = max(rows, key=lambda y: rows[y][1] - rows[y][0])
    left, right = rows[wy]
    mx = (left + right) // 2
    colm = np.nonzero(col[:, mx])[0]
    top, bot = colm.min(), colm.max()
    ref = a[top + 3 * Z, mx]
    lum = a[:, mx].sum(1)
    near = next((y for y in range(top + 2 * Z, bot) if col[y, mx] and lum[y] < lum[top + 3 * Z] - 60), bot)
    rim = a[min(bot - 2 * Z, near + 2 * Z), mx]
    v = VARIANTS[i] if i < len(VARIANTS) else ('?',) * 4
    print('%d\t%s\t%s\t%s\t%s\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%s\t%s' % (i + 1, v[0], v[1], v[2], v[3], left / Z, (right + 1) / Z, top / Z, near / Z, (bot + 1) / Z,
          '%d,%d,%d' % tuple(ref), '%d,%d,%d' % tuple(rim)))
