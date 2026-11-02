#!/usr/bin/env python3
"""meas.py DIR > HPROCESS-WORD.txt (Windows 01QbbApP): per print, every vector shape's bbox (circles ~ w==h, arrows) and text lines; then circle centres, gaps."""
import sys, os, pymupdf
for f in sorted(os.listdir(sys.argv[1])):
    if not f.endswith('-orig.pdf'): continue
    p = pymupdf.open(os.path.join(sys.argv[1], f))[0]
    print('==', f[:-9])
    sh = []
    for r in p.get_drawings():
        b = r['rect']
        if b.width < 3 and b.height < 3: continue
        sh.append((b.x0, b.y0, b.x1, b.y1, len(r['items']), r.get('fill')))
    sh.sort()
    circ = [s for s in sh if abs((s[2]-s[0])-(s[3]-s[1])) < 0.8 and s[2]-s[0] > 20]
    arr = [s for s in sh if s not in circ]
    for s in arr: print('  arrow/other x0 %.2f x1 %.2f y0 %.2f y1 %.2f items %d' % (s[0], s[2], s[1], s[3], s[4]))
    cs = [((s[0]+s[2])/2, s[2]-s[0], s[0], s[2], (s[1]+s[3])/2) for s in circ]
    for i, c in enumerate(cs): print('  circle%d cx %.2f d %.2f x0 %.2f x1 %.2f cy %.2f' % (i, c[0], c[1], c[2], c[3], c[4]))
    print('  gaps (edge to edge):', ' '.join('%.1f' % (cs[i+1][2]-cs[i][3]) for i in range(len(cs)-1)))
    print('  pitch (centre to centre):', ' '.join('%.1f' % (cs[i+1][0]-cs[i][0]) for i in range(len(cs)-1)))
    for b in p.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ''.join(s['text'] for s in l['spans']).strip()
            if t: print('  text %r size %.1f x %.1f..%.1f y %.1f' % (t[:40], l['spans'][0]['size'], l['bbox'][0], l['bbox'][2], l['bbox'][1]))
