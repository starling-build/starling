#!/usr/bin/env python3
"""meas2.py DIR > BAL3-LAB2-WORD.tsv : every text line of every page: doc, page, y_top, baseline_y, x0, kind, text[:50].
kind: LABEL (starts with 'Note ' , label paragraph), NOTETEXT, ITEM. Page-top = 0 (pt)."""
import sys, glob, os, pymupdf
print('# doc\tpage\tline_top\tbaseline\tx0\tkind\ttext')
for fn in sorted(glob.glob(os.path.join(sys.argv[1], '*-orig.pdf'))):
    name = os.path.basename(fn).split('-orig')[0]
    for pn, p in enumerate(pymupdf.open(fn), 1):
        rows = []
        for b in p.get_text('dict')['blocks']:
            for l in b.get('lines', []):
                t = ''.join(s['text'] for s in l['spans']).strip()
                if not t: continue
                kind = 'LABEL' if t.startswith('Note') and len(t) < 8 else ('NOTETEXT' if (t.startswith('NOTE-TEXT') or t[:1].islower() and False) else 'LINE')
                rows.append((l['bbox'][1], l['spans'][0]['origin'][1], l['bbox'][0], kind, t))
        for top, base, x0, kind, t in sorted(rows):
            print('%s\t%d\t%.2f\t%.2f\t%.2f\t%s\t%s' % (name, pn, top, base, x0, kind, t[:50]))
