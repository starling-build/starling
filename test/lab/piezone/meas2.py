#!/usr/bin/env python3
"""meas2.py DIR > PIE2-WORD.tsv (windows; pymupdf): per pz-TAG-orig.pdf, every chart (frame = a stroked rect >= 200 x 150 pt, several per
page, numbered top to bottom over all pages): pie centre (edge shared by the wedge boxes) and R, legend top, and each data label
('datalabelK, 2' or 'dKxxx, 2') with its centre, offset from the pie centre, box, in/out; then one LEADER row per grey two-piece line
(start, elbow, end) in that frame. Columns as pie1's meas.py plus 'chart' after doc."""
import sys, os, re, math, collections, pymupdf
print('# doc\tchart\tk\tcx\tcy\tdx\tdy\tdist\tw\th\tpie_cx\tpie_cy\tR\tlegend_top\tin_out\twrapped')
print('# LEADER rows: doc\tchart\tLEADER\tstart_x\tstart_y\telbow_x\telbow_y\tend_x\tend_y\tstart_minus_R')
for f in sorted(x for x in os.listdir(sys.argv[1]) if x.endswith('-orig.pdf')):
    doc = pymupdf.open(os.path.join(sys.argv[1], f)); n = 0
    for p in doc:
        dr = p.get_drawings()
        frames = sorted([d['rect'] for d in dr if d['type'] == 's' and d['rect'].width >= 200 and d['rect'].height >= 150], key=lambda r: r.y0)
        # (two strokes per frame: the border and the chart area; keep one per y)
        uniq = []
        for r in frames:
            if not uniq or abs(r.y0 - uniq[-1].y0) > 5: uniq.append(r)
        words = p.get_text('words')
        for fr in uniq:
            n += 1
            inside = lambda r: fr.contains(r)
            ws = [d['rect'] for d in dr if d.get('fill') and d['type'] == 'fs' and d['fill'] != (1.0, 1.0, 1.0) and d['rect'].width > 20 and d['rect'].height > 20 and inside(d['rect'])]
            if not ws: continue
            # (The pie's centre is the apex every wedge's straight sides meet at; R the apex's distance to the arc ends (on-curve
            # points, not the Bezier control points a wedge's box reaches). Works for 2 slices as for 12.)
            wd = [d for d in dr if d.get('fill') and d['type'] == 'fs' and d['fill'] != (1.0, 1.0, 1.0) and d['rect'].width > 20 and d['rect'].height > 20 and inside(d['rect'])]
            ends = collections.Counter(); lines = []
            for d in wd:
                for it in d['items']:
                    if it[0] == 'l':
                        a, b = (round(it[1].x, 1), round(it[1].y, 1)), (round(it[2].x, 1), round(it[2].y, 1))
                        ends[a] += 1; ends[b] += 1; lines.append((a, b))
            apex = ends.most_common(1)[0][0]; pcx, pcy = apex
            R = max(math.hypot(q[0] - pcx, q[1] - pcy) for a, b in lines for q in (a, b) if q != apex)
            fw = [w for w in words if fr.contains(pymupdf.Rect(w[:4]))]
            # legend top: first 'datalabelN' word (no comma) below the pie, else frame bottom
            lt = min([w[1] for w in fw if re.fullmatch(r'(datalabel|d)\d(x*)', w[4]) and w[1] > pcy + R], default=fr.y1)
            for i, w in enumerate(fw):
                m = re.fullmatch(r'(?:datalabel|d)(\d)x*,', w[4])
                if not m: continue
                x0, y0, x1, y1 = w[:4]; wrapped = ''
                if i + 1 < len(fw) and re.fullmatch(r'\d+', fw[i + 1][4]):
                    v = fw[i + 1]
                    if abs(v[1] - y0) < 2: x1 = max(x1, v[2])
                    else: y1 = max(y1, v[3]); x0 = min(x0, v[0]); x1 = max(x1, v[2]); wrapped = 'wrapped'
                cx = (x0 + x1) / 2; cy = (y0 + y1) / 2
                print('%s\t%d\t%s\t%.2f\t%.2f\t%+.2f\t%+.2f\t%.2f\t%.1f\t%.1f\t%.2f\t%.2f\t%.2f\t%.1f\t%s\t%s' % (f[:-9], n, m.group(1), cx, cy, cx - pcx, cy - pcy, math.hypot(cx - pcx, cy - pcy), x1 - x0, y1 - y0, pcx, pcy, R, lt, 'in' if math.hypot(cx - pcx, cy - pcy) < R else 'OUT', wrapped))
            for d in dr:
                if d['type'] != 's' or not d.get('color') or len(d['items']) != 2 or not inside(d['rect']): continue
                c = d['color']
                if not (0.5 < c[0] < 0.8 and abs(c[0] - c[1]) < 0.02): continue
                pts = [d['items'][0][1], d['items'][0][2], d['items'][1][2]]
                s, e, q = pts[0], pts[1], pts[2]
                if abs(math.hypot(q.x - pcx, q.y - pcy) - R) < abs(math.hypot(s.x - pcx, s.y - pcy) - R): s, q = q, s
                print('%s\t%d\tLEADER\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f' % (f[:-9], n, s.x, s.y, e.x, e.y, q.x, q.y, math.hypot(s.x - pcx, s.y - pcy) - R))
