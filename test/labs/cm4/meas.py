#!/usr/bin/env python3
"""meas.py PDF > CM1-WORD.tsv: every text line of every page: page, y_top, baseline, x0, text."""
import sys, pymupdf
print('# page\ty_top\tbaseline\tx0\ttext')
for pn, p in enumerate(pymupdf.open(sys.argv[1]), 1):
    rows = []
    for b in p.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ''.join(s['text'] for s in l['spans']).strip()
            if t: rows.append((l['bbox'][1], l['spans'][0]['origin'][1], l['bbox'][0], t))
    for top, base, x0, t in sorted(rows): print('%d\t%.2f\t%.2f\t%.1f\t%s' % (pn, top, base, x0, t))
