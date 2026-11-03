#!/usr/bin/env python3
"""meas2.py DIR > BDR2-WORD.tsv (Windows 01QbbApP, for amd-perf, lab bdr2).
Per doc, per page: every drawn item (kind, x0,y0,x1,y1, fill rgb, stroke rgb, stroke width) and every text line (baseline y, x0, text).
kind: fill = filled rect, line = a straight line, rect = a stroked rect. Rows sorted by y."""
import sys, os, glob, pymupdf
d = sys.argv[1]
print('# doc\tpage\tkind\tx0\ty0\tx1\ty1\tfill\tstroke\twidth\ttext')
def col(c): return '' if c is None else ','.join('%d' % round(v * 255) for v in c)
for f in sorted(glob.glob(os.path.join(d, '*-orig.pdf'))):
    k = os.path.basename(f)[:-9]
    for pg in pymupdf.open(f):
        rows = []
        for dr in pg.get_drawings():
            for it in dr['items']:
                if it[0] == 'l':
                    a, b = it[1], it[2]
                    rows.append((min(a.y, b.y), 'line', min(a.x, b.x), min(a.y, b.y), max(a.x, b.x), max(a.y, b.y), '', col(dr.get('color')), dr.get('width'), ''))
                elif it[0] == 're':
                    r = it[1]
                    rows.append((r.y0, 'fill' if dr.get('fill') and not dr.get('color') else 'rect', r.x0, r.y0, r.x1, r.y1, col(dr.get('fill')), col(dr.get('color')), dr.get('width'), ''))
        for b in pg.get_text('dict')['blocks']:
            for l in b.get('lines', []):
                t = ''.join(s['text'] for s in l['spans']).strip()
                if t: rows.append((l['spans'][0]['origin'][1], 'text', l['bbox'][0], l['spans'][0]['origin'][1], l['bbox'][2], l['bbox'][3], '', '', '', t[:20]))
        for r in sorted(rows, key=lambda r: (r[0], r[2])):
            print('%s\t%d\t%s\t%.2f\t%.2f\t%.2f\t%.2f\t%s\t%s\t%s\t%s' % (k, pg.number + 1, r[1], r[2], r[3], r[4], r[5], r[6], r[7], '' if r[8] in (None, '') else '%.2f' % r[8], r[9]))
