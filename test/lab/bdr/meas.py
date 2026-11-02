#!/usr/bin/env python3
"""meas.py DIR > BDR-WORD.tsv: per doc: the text line's bbox top/bottom + baseline, filled rects (shading) top/bottom/x, border lines (stroked/filled thin rects) y, per page."""
import sys, os, pymupdf
d = sys.argv[1]
print('# doc\tpage\tkind\ty_top\ty_bot\tx0\tx1\textra')
for k in ('bdrA', 'bdrB', 'bdrC', 'bdrD', 'bdrE'):
    for pg in pymupdf.open(os.path.join(d, k + '-orig.pdf')):
        for b in pg.get_text('dict')['blocks']:
            for l in b.get('lines', []):
                t = ''.join(s['text'] for s in l['spans'])
                if t.strip(): print('%s\t%d\ttext\t%.2f\t%.2f\t%.2f\t%.2f\tbase %.2f %s' % (k, pg.number + 1, l['bbox'][1], l['bbox'][3], l['bbox'][0], l['bbox'][2], l['spans'][0]['origin'][1], t))
        for dr in pg.get_drawings():
            r = dr['rect']
            print('%s\t%d\tdraw\t%.2f\t%.2f\t%.2f\t%.2f\ttype %s fill %s color %s w %s' % (k, pg.number + 1, r.y0, r.y1, r.x0, r.x1, dr['type'], dr.get('fill'), dr.get('color'), dr.get('width')))
