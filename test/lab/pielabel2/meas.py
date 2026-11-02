#!/usr/bin/env python3
"""meas.py DIR > PIELABEL2-WORD.tsv  (Windows 01QbbApP). For every pie-*-orig.pdf: every text line on page 1 near the chart (not 'Table'),
centre relative to the fixed pie centre (127.8,229.6), R 53.4. cols: doc, text, dx, dy, w, h, dist, where(in|OUT).
Label with no line at all in the chart box -> 'NONE'. Lines come in order top to bottom."""
import sys, os, math, pymupdf
CX, CY, R = 127.8, 229.6, 53.4
print('# doc\ttext\tdx\tdy\twidth\theight\tdist\tinside_pie')
for f in sorted(os.listdir(sys.argv[1])):
    if not f.endswith('-orig.pdf'): continue
    page = pymupdf.open(os.path.join(sys.argv[1], f))[0]
    name = f[:-9]
    n = 0
    for b in page.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ''.join(s['text'] for s in l['spans']).strip()
            bx = pymupdf.Rect(l['bbox'])
            if not t or 'Table' in t or abs((bx.x0 + bx.x1) / 2 - CX) > 130 or abs((bx.y0 + bx.y1) / 2 - CY) > 130: continue
            dx, dy = (bx.x0 + bx.x1) / 2 - CX, (bx.y0 + bx.y1) / 2 - CY
            d = math.hypot(dx, dy)
            print('%s\t%s\t%+.1f\t%+.1f\t%.1f\t%.1f\t%.1f\t%s' % (name, t, dx, dy, bx.width, bx.height, d, 'in' if d < R else 'OUT'))
            n += 1
    if n == 0: print('%s\tNONE' % name)
