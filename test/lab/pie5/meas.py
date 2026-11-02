import pymupdf, numpy as np, os, sys
S = 4
FX, FY, FW, FH = 72.0, 72.0, 400.7, 216.0
rows = []
for nm in ('best', 'inEnd', 'outEnd', 'ctr'):
    d = pymupdf.open('run/pie5-%s-orig.pdf' % nm)
    for pn, p in enumerate(d, 1):
        names = 'short' if pn <= 4 else 'long'; rot = [0, 90, 180, 270][(pn - 1) % 4]
        pm = p.get_pixmap(matrix=pymupdf.Matrix(S, S)); a = np.frombuffer(pm.samples, np.uint8).reshape(pm.height, pm.width, 3).astype(int)
        words = [w for w in p.get_text('words')]
        # labels: lines of words (name line + pct line); group words whose x-centres are within 14pt and y gap < 3
        pct = [w for w in words if w[4].endswith('%')]
        # pie mask: colored/gray fill pixels inside frame, minus text pixels
        mask = (a.max(axis=2) - a.min(axis=2) > 15) | ((a.max(axis=2) < 200) & (a.min(axis=2) > 70))
        sub = np.zeros_like(mask); y0, y1, x0, x1 = int((FY + 3) * S), int((FY + FH - 3) * S), int((FX + 3) * S), int((FX + FW - 3) * S); sub[y0:y1, x0:x1] = mask[y0:y1, x0:x1]
        ys, xs = np.where(sub)
        pie = (xs.min() / S, ys.min() / S, xs.max() / S, ys.max() / S)
        for w in sorted(pct, key=lambda w: w[0]):
            nmw = [u for u in words if not u[4].endswith('%') and abs((u[0] + u[2]) / 2 - (w[0] + w[2]) / 2) < 10 and 0 < w[1] - u[1] < 16]
            if not nmw: continue
            n = nmw[0]
            bb = (min(n[0], w[0]), n[1], max(n[2], w[2]), w[3])
            ix0, iy0, ix1, iy1 = [int(v * S) for v in bb]
            reg = a[iy0:iy1, ix0:ix1]; txt = reg.max(axis=2) < 110
            bgm = ~txt; cm = mask[iy0:iy1, ix0:ix1] & bgm
            frac = cm.sum() / max(1, bgm.sum())
            rows.append((nm, names, rot, n[4], w[4], round((bb[0] + bb[2]) / 2 - FX, 1), round((bb[1] + bb[3]) / 2 - FY, 1), 'inside' if frac > 0.5 else ('edge' if frac > 0.1 else 'outside'), round(frac, 2),
                         round(pie[0] - FX, 1), round(pie[1] - FY, 1), round(pie[2] - FX, 1), round(pie[3] - FY, 1)))
with open('PIE5-WORD.tsv', 'w', encoding='utf8') as o:
    o.write('# set\tnames\trotY\tcat\tpct\tlabel_cx\tlabel_cy (pt from frame top-left; frame 400.7x216)\tinside/outside\tcolored_frac\tpie_x0\tpie_y0\tpie_x1\tpie_y1 (visible pie bbox in frame pt)\n')
    for r in rows: o.write('\t'.join(map(str, r)) + '\n')
print(len(rows))
for nm in ('best', 'inEnd', 'outEnd', 'ctr'):
    for names in ('short', 'long'):
        for rot in (0, 90, 180, 270):
            rr = [r for r in rows if r[0] == nm and r[1] == names and r[2] == rot]
            print(nm, names, rot, ' '.join('%s:%s(%.0f,%.0f)' % (r[4], r[7][0], r[5], r[6]) for r in sorted(rr, key=lambda r: float(r[4][:-1]))))
