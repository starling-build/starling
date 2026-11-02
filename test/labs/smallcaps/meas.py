#!/usr/bin/env python3
"""meas.py PDF > SMALLCAPS-WORD.tsv: per line: face, requested pt (from build.py order), the sizes pymupdf reports (size of full caps / of the small-caps letters), the pdf font, line advance width (first char origin to last char end), pixel ink width at 8 px/pt."""
import sys, numpy as np, pymupdf
ORDER = [(f, p) for f in ('TNR', 'Arial') for p in (9, 10, 11, 12, 13, 14)] + [('TNR', '11 mixed'), ('Arial', '11 mixed')] + [(f, p) for f in ('TNR', 'Arial') for p in (9.5, 10.5, 11.5, 12.5)]
p = pymupdf.open(sys.argv[1])[0]
lines = []
for b in p.get_text('rawdict')['blocks']:
    for l in b.get('lines', []):
        cs = [c for s in l['spans'] for c in s['chars']]
        if cs: lines.append((l, cs))
lines.sort(key=lambda t: t[0]['bbox'][1])
print('# line\tface\tpt\tsizes (size:count of glyphs)\tfont\tadvance_w\tink_L\tink_R\tink_w\ttext')
for i, (l, cs) in enumerate(lines):
    sz = {}
    for s in l['spans']:
        for c in s['chars']:
            if c['c'].strip(): sz[round(s['size'], 3)] = sz.get(round(s['size'], 3), 0) + 1
    # per-glyph size via spans: collect (char, size) for letters at different sizes
    adv = cs[-1]['bbox'][2] - cs[0]['origin'][0]
    r = pymupdf.Rect(l['bbox']); r.x1 += 2; r.x0 -= 2
    pm = p.get_pixmap(matrix=pymupdf.Matrix(8, 8), clip=r)
    a = np.frombuffer(pm.samples, np.uint8).reshape(pm.height, pm.width, pm.n)[:, :, :3].min(axis=2)
    xs = np.nonzero((a < 128).any(axis=0))[0]
    L = r.x0 + xs.min() / 8; R = r.x0 + (xs.max() + 1) / 8
    face, pt = ORDER[i]
    print('%d\t%s\t%s\t%s\t%s\t%.2f\t%.2f\t%.2f\t%.2f\t%s' % (i, face, pt, ' '.join('%s:%d' % kv for kv in sorted(sz.items())), l['spans'][0]['font'], adv, L, R, R - L, ''.join(c['c'] for c in cs)[:20]))
