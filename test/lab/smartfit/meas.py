#!/usr/bin/env python3
"""meas.py PDF... -> per PDF: the text lines (size, bbox) and the filled rectangles, one line each."""
import sys, pymupdf
for f in sys.argv[1:]:
    p = pymupdf.open(f)[0]
    print('==', f)
    for d in p.get_drawings():
        if d.get('fill') and d['rect'].width < 700: print('rect', [round(x, 1) for x in d['rect']])
    for b in p.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            print('text', round(l['spans'][0]['size'], 1), [round(x, 1) for x in l['bbox']], ''.join(s['text'] for s in l['spans'])[:30])
