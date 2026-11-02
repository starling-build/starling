#!/usr/bin/env python3
"""meas.py PDF -> one TSV row per table: label, left rule x, AAAA x, BBBB x, middle rule x, right rule x
(rule x = centre of each vertical line/thin rect; text x = left of the glyphs). Needs PyMuPDF."""
import sys, re
import pymupdf
d = pymupdf.open(sys.argv[1]); rows = []
print('label\tleft_rule\tAAAA\tmid_rule\tBBBB\tright_rule')
for pg in d:
    words = pg.get_text('words'); vs = []
    for dr in pg.get_drawings():
        r = dr['rect']
        if r.height > 12 and r.width < 4: vs.append(((r.x0 + r.x1) / 2, r.y0, r.y1))
    labs = [w for w in words if re.fullmatch(r'T\d+', w[4])]
    for k, l in enumerate(labs):
        y0 = l[1]; y1 = labs[k + 1][1] if k + 1 < len(labs) else 1e9
        line = ' '.join(w[4] for w in words if abs(w[1] - l[1]) < 2)
        a = [w for w in words if w[4] == 'AAAA' and y0 < w[1] < y1]; b = [w for w in words if w[4] == 'BBBB' and y0 < w[1] < y1]
        xs = sorted({round(x, 2) for x, ya, yb in vs if y0 < ya < y1})
        if a and b and len(xs) >= 3: print('\t'.join([line, str(xs[0]), f'{a[0][0]:.2f}', str(xs[len(xs) // 2]), f'{b[0][0]:.2f}', str(xs[-1])]))
        else: print(line + '\t?\t?\t?\t?\t?')
