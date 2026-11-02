#!/usr/bin/env python3
"""meas.py PDF [pages] : every text line in the footer zone (y > 700) of the given pages: page, y0,y1, x0,x1, text (repr), size, colour, plus all 'X'/'Y' glyphs on the page."""
import sys, pymupdf
d = pymupdf.open(sys.argv[1])
pages = [int(a) for a in sys.argv[2:]] or range(1, len(d) + 1)
for pn in pages:
    p = d[pn - 1]
    for b in p.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            if l['bbox'][1] < 700: continue
            for s in l['spans']:
                print('p%d\ty %.1f..%.1f\tx %.1f..%.1f\t%r\tsize %.1f\tcolour %06x\t%s' % (pn, s['bbox'][1], s['bbox'][3], s['bbox'][0], s['bbox'][2], s['text'], s['size'], s['color'], s['font']))
