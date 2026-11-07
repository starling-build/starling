#!/usr/bin/env python3
"""rc.py DIR > PIE3-WORD.tsv (Windows 01QbbApP, for amd-1): per p3-n<N>-a<ANG>[-nolab]-orig.pdf: pie centre = the path vertex shared by the most wedge fills
(averaged over its near-identical copies), radius = farthest wedge path point from it; plus N, ANG, nolab and the wedge count."""
import sys, os, re, math, collections, pymupdf
print('# name\tN\tANG\tnolab\tR\tcx\tcy\twedges')
for f in sorted(x for x in os.listdir(sys.argv[1]) if x.endswith('-orig.pdf')):
    m = re.match(r'p3-n(\d+)-a(\d+)(-nolab)?-orig\.pdf', f); nl = 'nolab' if m.group(3) else ''
    p = pymupdf.open(os.path.join(sys.argv[1], f))[0]
    dr = [d for d in p.get_drawings() if d.get('fill') and d['type'] in ('f', 'fs') and d['fill'] != (1.0, 1.0, 1.0) and d['rect'].width > 20 and d['rect'].height > 20]
    pts = []; vc = collections.Counter()
    for d in dr:
        seen = set()
        for it in d['items']:
            for q in it[1:]:
                if hasattr(q, 'x'): pts.append((q.x, q.y)); seen.add((round(q.x, 1), round(q.y, 1)))
        for v in seen: vc[v] += 1
    if not pts: print('%s\t%s\t%s\t%s\tnone' % (f[:-9], m.group(1), m.group(2), nl)); continue
    mx = max(vc.values()); top = [v for v, c in vc.items() if c == mx]
    mean = (sum(v[0] for v in top) / len(top), sum(v[1] for v in top) / len(top))
    (px, py) = min(top, key=lambda v: math.hypot(v[0] - mean[0], v[1] - mean[1]))
    near = [q for q in pts if abs(q[0] - px) < 0.3 and abs(q[1] - py) < 0.3]
    cx = sum(q[0] for q in near) / len(near); cy = sum(q[1] for q in near) / len(near)
    R = max(math.hypot(q[0] - cx, q[1] - cy) for q in pts)
    print('%s\t%s\t%s\t%s\t%.2f\t%.2f\t%.2f\t%d' % (f[:-9], m.group(1), m.group(2), nl, R, cx, cy, len(dr)))
