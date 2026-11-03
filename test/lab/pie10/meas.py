import pymupdf, numpy as np, sys
import gen
S = 4
FX, FY, FW, FH = 72.0, 72.0, 400.7, 216.0
d = pymupdf.open(sys.argv[1] if len(sys.argv) > 1 else 'pie10-orig.pdf')
rows = []
for pn, (s, nk, ry, ps) in enumerate(gen.combos()):
    p = d[pn]
    sh = gen.SETS[s]; nm = gen.names(nk, len(sh))
    pm = p.get_pixmap(matrix=pymupdf.Matrix(S, S)); a = np.frombuffer(pm.samples, np.uint8).reshape(pm.height, pm.width, 3).astype(int)
    words = p.get_text('words')
    mask = (a.max(axis=2) - a.min(axis=2) > 15) | ((a.max(axis=2) < 200) & (a.min(axis=2) > 70))
    sub = np.zeros_like(mask); y0, y1, x0, x1 = int((FY + 3) * S), int((FY + FH - 3) * S), int((FX + 3) * S), int((FX + FW - 3) * S); sub[y0:y1, x0:x1] = mask[y0:y1, x0:x1]
    ys, xs = np.where(sub)
    pie = (xs.min() / S - FX, ys.min() / S - FY, xs.max() / S - FX, ys.max() / S - FY)
    cum = 0
    for i, n in enumerate(nm):
        a0 = cum; cum += sh[i]
        nw = [w for w in words if w[4] == n]
        if not nw:
            rows.append((pn + 1, s, nk, ry, ps, i, n, '%d%%' % sh[i], 'MISSING')); continue
        n_ = nw[0]
        pw = [w for w in words if w[4] == '%d%%' % sh[i] and abs((w[0] + w[2]) / 2 - (n_[0] + n_[2]) / 2) < 12 and 0 < w[1] - n_[1] < 16]
        if not pw:
            rows.append((pn + 1, s, nk, ry, ps, i, n, '%d%%' % sh[i], 'NOPCT')); continue
        w = pw[0]
        bb = (min(n_[0], w[0]), n_[1], max(n_[2], w[2]), w[3])
        ix0, iy0, ix1, iy1 = [int(v * S) for v in bb]
        reg = a[iy0:iy1, ix0:ix1]; txt = reg.max(axis=2) < 110
        bgm = ~txt; cm = mask[iy0:iy1, ix0:ix1] & bgm
        frac = cm.sum() / max(1, bgm.sum())
        rows.append((pn + 1, s, nk, ry, ps, i, n, '%d%%' % sh[i], round((bb[0] + bb[2]) / 2 - FX, 1), round((bb[1] + bb[3]) / 2 - FY, 1), round(bb[2] - bb[0], 1), round(bb[3] - bb[1], 1),
                     'inside' if frac > 0.5 else ('edge' if frac > 0.1 else 'outside'), round(frac, 2), round(pie[0], 1), round(pie[1], 1), round(pie[2], 1), round(pie[3], 1), a0, cum))
with open(sys.argv[2] if len(sys.argv) > 2 else 'PIE10-WORD.tsv', 'w', encoding='utf8') as o:
    o.write('# page\tset\tnames\trotY\tpersp\tslice_idx\tcat\tpct\tlabel_cx\tlabel_cy (frame pt from top-left, 400.7x216)\tw\th\tinside/outside\tcolored_frac\tpie_x0\tpie_y0\tpie_x1\tpie_y1 (visible pie bbox)\tcum_from_pct\tcum_to_pct\n')
    for r in rows:
        o.write('\t'.join(map(str, r)) + '\n')
print(len(rows), 'rows;', sum(1 for r in rows if len(r) < 12), 'unmatched')
