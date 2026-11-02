#!/usr/bin/env python3
"""meas.py DIR > PIEEQ-WORD.tsv (Windows 01QbbApP, for amd-1): per pieeq-N-{b,r,none}-orig.pdf: pie centre (the edge value shared by the wedge boxes) and radius,
legend top, and every outside data label ('datalabelK, 2', found from words) with its centre (cx,cy), offset from the pie centre (dx,dy), box w/h and distance."""
import sys, os, re, math, collections, pymupdf
print('# doc\tk\tcx\tcy\tdx\tdy\tdist\tw\th\tpie_cx\tpie_cy\tR\tlegend_top')
for f in sorted([x for x in os.listdir(sys.argv[1]) if x.endswith('-orig.pdf')], key=lambda s: (int(s.split('-')[1]), s)):
    p = pymupdf.open(os.path.join(sys.argv[1], f))[0]
    ws = [d['rect'] for d in p.get_drawings() if d.get('fill') and d['type'] == 'fs' and d['fill'] != (1.0, 1.0, 1.0) and d['rect'].width > 20 and d['rect'].height > 20]
    cnt = collections.Counter(); cny = collections.Counter()
    for r in ws:
        for v in (round(r.x0, 1), round(r.x1, 1)): cnt[v] += 1
        for v in (round(r.y0, 1), round(r.y1, 1)): cny[v] += 1
    pcx = cnt.most_common(1)[0][0]; pcy = cny.most_common(1)[0][0]
    R = max(max(r.x1 - pcx, pcx - r.x0, r.y1 - pcy, pcy - r.y0) for r in ws)
    words = sorted(p.get_text('words'), key=lambda w: (w[5], w[6], w[7]))
    lt = min([w[1] for w in words if re.fullmatch(r'datalabel\d+', w[4])] or [float('nan')])
    for i, w in enumerate(words):
        m = re.fullmatch(r'datalabel(\d+),', w[4]); parts = None
        if m and i + 1 < len(words): parts = [w, words[i + 1]]; k = m.group(1)
        elif w[4] == 'datalabel' and i + 2 < len(words) and re.fullmatch(r'\d+,', words[i + 1][4]): parts = [w, words[i + 1], words[i + 2]]; k = words[i + 1][4][:-1]
        if not parts: continue
        x0 = min(q[0] for q in parts); x1 = max(q[2] for q in parts); y0 = min(q[1] for q in parts); y1 = max(q[3] for q in parts); cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        m = type('M', (), {'group': lambda self, n, k=k: k})()
        wrapped = 'wrapped' if len(parts) == 3 else ''
        print('%s\t%s\t%.2f\t%.2f\t%+.2f\t%+.2f\t%.2f\t%.1f\t%.1f\t%.2f\t%.2f\t%.2f\t%.1f	%s	%s' % (f[:-9], m.group(1), cx, cy, cx - pcx, cy - pcy, math.hypot(cx - pcx, cy - pcy), x1 - x0, y1 - y0, pcx, pcy, R, lt, 'in' if math.hypot(cx - pcx, cy - pcy) < R else 'OUT', wrapped))
