#!/usr/bin/env python3
"""meas.py DIR > HP3-WORD.tsv (Windows 01QbbApP, for amd-perf): per print hp3_n*_{eq,long}-orig.pdf:
circles are raster pairs (a 30.6pt shadow and a ~25pt circle image); centre = middle of the ~25-26pt image. Prints n, centres, pitch, the arrow's left/right (vector path and its raster shadow),
and the y (line bbox top and baseline) of every text line 'Word' above (y<180) / below (y>210) the circles, with x0..x1 and the text centre x."""
import sys, os, pymupdf
for f in sorted(os.listdir(sys.argv[1])):
    if not f.endswith('-orig.pdf'): continue
    p = pymupdf.open(os.path.join(sys.argv[1], f))[0]
    ii = [i['bbox'] for i in p.get_image_info()]
    arrow_img = max(ii, key=lambda b: b[2] - b[0])
    circ = sorted([b for b in ii if 22 < b[2] - b[0] < 28 and abs((b[2] - b[0]) - (b[3] - b[1])) < 1.5])
    cx = [(b[0] + b[2]) / 2 for b in circ]
    vec = [d['rect'] for d in p.get_drawings() if d['rect'].width > 300]
    print('==', f[:-9], 'n=%d' % len(cx))
    print('circle_cx', ' '.join('%.2f' % x for x in cx))
    print('pitch', ' '.join('%.2f' % (cx[i + 1] - cx[i]) for i in range(len(cx) - 1)))
    print('circle_cy %.2f d %.2f' % ((circ[0][1] + circ[0][3]) / 2, circ[0][2] - circ[0][0]))
    print('arrow_img x0 %.2f x1 %.2f | vector %s' % (arrow_img[0], arrow_img[2], ' '.join('%.2f..%.2f' % (r.x0, r.x1) for r in vec)))
    for b in p.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ''.join(s['text'] for s in l['spans']).strip()
            if t != 'Word': continue
            y = l['spans'][0]['origin'][1]
            print('text\t%s\tx %.2f..%.2f\tcx %.2f\ttop %.2f\tbase %.2f' % ('above' if y < 180 else 'below', l['bbox'][0], l['bbox'][2], (l['bbox'][0] + l['bbox'][2]) / 2, l['bbox'][1], y))
