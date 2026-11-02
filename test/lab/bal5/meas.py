#!/usr/bin/env python3
"""meas.py DIR > BAL3O-WORD.tsv: per doc/page every balloon: its outlined rect (drawings with x0 in 425..445, w>150) in order top to bottom:
doc page n x0 y0 y1 h dy(top-to-top pitch) text-inside. Text = words whose centre lies in the rect, joined ('' = empty balloon)."""
import sys, glob, os, pymupdf
print('# doc\tpage\tn\tx0\ty0\ty1\th\tpitch\ttext')
for fn in sorted(glob.glob(os.path.join(sys.argv[1], '*-orig.pdf'))):
    name = os.path.basename(fn).split('-orig')[0]
    for pn, p in enumerate(pymupdf.open(fn), 1):
        seen = set(); rs = []
        for d in p.get_drawings():
            r = d['rect']
            if 425 < r.x0 < 445 and r.width > 150 and r.height > 5:
                k = (round(r.x0, 1), round(r.y0, 1), round(r.y1, 1))
                if k not in seen: seen.add(k); rs.append(r)
        rs.sort(key=lambda r: r.y0)
        words = p.get_text('words'); prev = None
        for k, r in enumerate(rs, 1):
            t = ' '.join(w[4] for w in sorted(words, key=lambda w: (round(w[1]), w[0])) if r.x0 <= (w[0] + w[2]) / 2 <= r.x1 and r.y0 <= (w[1] + w[3]) / 2 <= r.y1)
            print('%s\t%d\t%d\t%.1f\t%.2f\t%.2f\t%.2f\t%s\t%s' % (name, pn, k, r.x0, r.y0, r.y1, r.height, '' if prev is None else '%.2f' % (r.y0 - prev), t))
            prev = r.y0
        print('# %s p%d: %d balloons, page h %.0f' % (name, pn, len(rs), p.rect.height))
