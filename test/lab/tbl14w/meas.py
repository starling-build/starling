#!/usr/bin/env python3
"""meas.py PDF -> TSV: label, number of text lines in the cell (1 = MMMMMMMM fits, 2 = wrapped), then per
(style, margin) the smallest delta that fits. Needs PyMuPDF."""
import sys, re, collections
import pymupdf
d = pymupdf.open(sys.argv[1]); items = []
for pg in d:
    ws = pg.get_text('words')
    labs = sorted([w for w in ws if re.fullmatch(r'T\d+', w[4])], key=lambda w: w[1])
    for k, l in enumerate(labs):
        y1 = labs[k + 1][1] if k + 1 < len(labs) else 1e9
        line = ' '.join(w[4] for w in ws if abs(w[1] - l[1]) < 2)
        body = [w for w in ws if l[1] + 3 < w[1] < y1 and re.fullmatch(r'M+', w[4])]
        ys = sorted({round(w[1], 0) for w in body})
        items.append((line, len(ys)))
fit = collections.OrderedDict()
print('label\tlines')
for line, n in items:
    print(f'{line}\t{n}')
    p = line.split()
    key = ' '.join(p[1:3]); dl = int(p[3][1:])
    if n == 1 and (key not in fit or dl < fit[key]): fit[key] = dl
print('\nsmallest delta (twips) that fits on one line:')
for k, v in fit.items(): print(f'{k}\t{v}')
