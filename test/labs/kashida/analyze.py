#!/usr/bin/env python3
"""analyze.py PDF > TSV: page, label, line_no, x0, x1, words, text-start. Needs PyMuPDF."""
import sys, pymupdf
d = pymupdf.open(sys.argv[1]); print('page\tlabel\tline\tx0\tx1\twords\tstart')
for pn, pg in enumerate(d, 1):
    label = ''; n = 0
    for b in pg.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ''.join(s['text'] for s in l['spans']).strip()
            if not t: continue
            if ' / right ' in t: label = t; n = 0; continue
            n += 1; x0, y0, x1, y1 = l['bbox']
            print('%d\t%s\t%d\t%.1f\t%.1f\t%d\t%s' % (pn, label, n, x0, x1, len(t.split()), t[:30]))
