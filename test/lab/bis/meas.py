#!/usr/bin/env python3
"""meas.py DIR > BIS-WORD.tsv: per bis-v?-orig.pdf, on the page holding '公民社會': baselines of 相關政府 (row 1 cell 2 first line) and 公民社會 (row 2 first line), the left merged cell's 其 and 員 y,
and the horizontal border segments (y, x0-x1, thickness) of cell 2's column (x 125..200) in y [first-60, last+40]; 'gap' = row 2 top - row 1 bottom when two adjacent segments."""
import sys, os, re, pymupdf
print('# doc\tpage\tkind\ty\tx0\tx1\textra')
for f in sorted([x for x in os.listdir(sys.argv[1]) if x.endswith('-orig.pdf')], key=lambda s: int(re.search(r'v(\d+)', s).group(1))):
    pdf = pymupdf.open(os.path.join(sys.argv[1], f)); name = f.replace('-orig.pdf', '')
    for pn, p in enumerate(pdf, 1):
        ws = p.get_text('words')
        g = [w for w in ws if w[4].startswith('公民社會')]
        if not g: continue
        r1 = ([w for w in ws if w[4].startswith('相關政府') or w[4].startswith('相關')] or [None])[0]
        if r1 is None: print('%s	%d	NOTEXT	' % (name, pn)); continue
        qi = ([w for w in ws if w[4] == '其'] or [(0, 0, 0, 0)])[0]; yuan = ([w for w in ws if w[4] == '員'] or [(0, 0, 0, 0)])[0]
        print('%s\t%d\ttext\t%.2f\t%.1f\t%.1f\t相關政府 top' % (name, pn, r1[1], r1[0], r1[2]))
        print('%s\t%d\ttext\t%.2f\t%.1f\t%.1f\t公民社會 top' % (name, pn, g[0][1], g[0][0], g[0][2]))
        print('%s\t%d\ttext\t%.2f\t%.1f\t%.1f\t其 top' % (name, pn, qi[1], qi[0], qi[2]))
        print('%s\t%d\ttext\t%.2f\t%.1f\t%.1f\t員 top' % (name, pn, yuan[1], yuan[0], yuan[2]))
        lo, hi = r1[1] - 60, g[0][1] + 20
        segs = []
        for d in p.get_drawings():
            q = d['rect']
            if q.height < 1.5 and q.width > 20 and lo < q.y0 < hi and q.x0 < 200 and q.x1 > 125: segs.append((round((q.y0 + q.y1) / 2, 2), round(q.x0, 1), round(q.x1, 1), round(q.height, 2)))
        for s in sorted(set(segs)): print('%s\t%d\thseg\t%.2f\t%.1f\t%.1f\th%.2f' % (name, pn, s[0], s[1], s[2], s[3]))
        vs = sorted(set((round(q['rect'].x0, 1), round(q['rect'].y0, 2), round(q['rect'].y1, 2)) for q in p.get_drawings() if q['rect'].width < 1.5 and q['rect'].height > 5 and lo < q['rect'].y1 < hi + 80 and 90 < q['rect'].x0 < 140))
        for v in vs: print('%s\t%d\tvseg\t%.2f\t%.1f\t%.2f\t' % (name, pn, v[1], v[0], v[2]))
