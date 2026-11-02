#!/usr/bin/env python3
"""meas.py DIR > VM1-WORD.tsv: per doc the distinct y of horizontal border lines (right col x>60+34) and (left col), plus text baselines."""
import sys, glob, os, pymupdf
for fn in sorted(glob.glob(os.path.join(sys.argv[1], '*-orig.pdf'))):
    name = os.path.basename(fn).split('-orig')[0]; p = pymupdf.open(fn)[0]
    segs = []
    for d in p.get_drawings():
        r = d['rect']
        if r.height < 1.5 and r.width > 5: segs.append((round((r.y0 + r.y1) / 2, 2), round(r.x0, 1), round(r.x1, 1)))
        elif r.width < 1.5 and r.height > 5: segs.append(('V', round((r.x0 + r.x1) / 2, 1), round(r.y0, 2), round(r.y1, 2)))
    print('#', name)
    for s in sorted(set(x for x in segs), key=str): print(name, 'seg', s)
    for b in p.get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            t = ''.join(c['c'] for s in l['spans'] for c in s['chars'])
            print(name, 'text', '%.2f' % l['spans'][0]['origin'][1], '%.1f' % l['bbox'][0], t)
