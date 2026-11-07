#!/usr/bin/env python3
"""leaders.py DIR > LEADERS1-WORD.tsv (Windows 01QbbApP): per *-orig.pdf page 1, every grey two-piece stroked line (a leader) with its start,
elbow and end points, the start's distance from the pie centre minus R (0 = on the rim), and the nearest outside label (datalabelK) to its end.
Docs with no leader get a '-' row. Labels found as in meas.py."""
import sys, os, re, math, collections, pymupdf
print('# doc\tlabel\tstart_x\tstart_y\telbow_x\telbow_y\tend_x\tend_y\tstart_minus_R\tend_to_label_dist')
for f in sorted(x for x in os.listdir(sys.argv[1]) if x.endswith('-orig.pdf')):
    p = pymupdf.open(os.path.join(sys.argv[1], f))[0]
    ws = [d['rect'] for d in p.get_drawings() if d.get('fill') and d['type'] == 'fs' and d['fill'] != (1.0, 1.0, 1.0) and d['rect'].width > 20 and d['rect'].height > 20]
    cnt = collections.Counter(); cny = collections.Counter()
    for r in ws:
        for v in (round(r.x0, 1), round(r.x1, 1)): cnt[v] += 1
        for v in (round(r.y0, 1), round(r.y1, 1)): cny[v] += 1
    if not ws: print(f[:-9] + '\t-\tno wedges'); continue
    pcx = cnt.most_common(1)[0][0]; pcy = cny.most_common(1)[0][0]
    R = max(max(r.x1 - pcx, pcx - r.x0, r.y1 - pcy, pcy - r.y0) for r in ws)
    words = sorted(p.get_text('words'), key=lambda w: (w[5], w[6], w[7]))
    labs = {}
    for i, w in enumerate(words):
        m = re.fullmatch(r'datalabel(\d+),', w[4]); parts = None
        if m and i + 1 < len(words): parts = [w, words[i + 1]]; k = m.group(1)
        elif w[4] == 'datalabel' and i + 2 < len(words) and re.fullmatch(r'\d+,', words[i + 1][4]): parts = [w, words[i + 1], words[i + 2]]; k = words[i + 1][4][:-1]
        if not parts: continue
        labs[k] = ((min(q[0] for q in parts) + max(q[2] for q in parts)) / 2, (min(q[1] for q in parts) + max(q[3] for q in parts)) / 2)
    n = 0
    for d in p.get_drawings():
        c = d.get('color')
        if d['type'] != 's' or not c or abs(c[0] - c[1]) > 0.01 or not (0.4 < c[0] < 0.8): continue
        its = [it for it in d['items'] if it[0] == 'l']
        if len(its) != 2 or len(d['items']) != 2: continue
        a, b, e = its[0][1], its[0][2], its[1][2]
        sm = math.hypot(a.x - pcx, a.y - pcy) - R
        k, dist = min(((k, math.hypot(e.x - lx, e.y - ly)) for k, (lx, ly) in labs.items()), key=lambda t: t[1], default=('?', float('nan')))
        print('%s\t%s\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%+.1f\t%.1f' % (f[:-9], k, a.x, a.y, b.x, b.y, e.x, e.y, sm, dist)); n += 1
    if not n: print(f[:-9] + '\t-\tno leaders')
