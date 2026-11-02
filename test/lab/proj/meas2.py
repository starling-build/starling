#!/usr/bin/env python3
"""meas2.py proj.pdf > PROJ-WORD.tsv  (Windows 01QbbApP; replaces meas.py for Word's print).
Word prints a 3-D chart as ONE RASTER IMAGE (1051x773 px at 96-dpi-ish, placed 377.9 x 278.0 pt inside the 400x300 frame), so there are no vector
wall/floor segments to read. This renders each page at 4 px/pt, takes the near-black pixels (max channel < 70, excludes the coloured bars),
runs a Hough transform (numpy only) and prints each straight line found as a segment: endpoints = each unbroken (gap < 1.5 pt) run >= 15 pt of black pixels within 1.2 px of the line (one row per run; runs of the same 'lineN' tag are collinear, a wall/bar hiding the line splits it); lines with < 150 px support are dropped.
Columns: page, x0, y0, x1, y1 (frame pt from its top left, the frame = page 72,72), length, support_px, lineN (same N = same fitted line).  Also prints the image bbox on a '#img' row."""
import sys, numpy as np, pymupdf
FX = FY = 72.0
S = 4
d = pymupdf.open(sys.argv[1])
print('# page\tx0\ty0\tx1\ty1\tlength_pt\tsupport_px (frame pt from top-left; Hough segments of the black outlines; rendering %d px/pt)' % S)
for pn, p in enumerate(d, 1):
    info = p.get_image_info()
    if info:
        b = info[0]['bbox']
        print('#img\t%d\t%.2f\t%.2f\t%.2f\t%.2f' % (pn, b[0] - FX, b[1] - FY, b[2] - FX, b[3] - FY))
    clip = pymupdf.Rect(FX, FY, FX + 400, FY + 300)
    pm = p.get_pixmap(matrix=pymupdf.Matrix(S, S), clip=clip)
    a = np.frombuffer(pm.samples, np.uint8).reshape(pm.height, pm.width, pm.n)[:, :, :3].astype(int)
    m = a.max(axis=2) < 70
    # drop the thin frame border if present at the very edge
    m[:3, :] = m[-3:, :] = False; m[:, :3] = m[:, -3:] = False
    ys, xs = np.nonzero(m)
    if len(xs) == 0:
        print('%d\tNONE' % pn); continue
    th = np.deg2rad(np.arange(0, 180, 0.25))
    ct, st = np.cos(th), np.sin(th)
    rmax = int(np.hypot(m.shape[0], m.shape[1])) + 2
    acc = np.zeros((len(th), 2 * rmax + 1), np.int32)
    for i in range(len(th)):
        r = np.rint(xs * ct[i] + ys * st[i]).astype(int) + rmax
        acc[i] += np.bincount(r, minlength=2 * rmax + 1)
    used = np.zeros(len(xs), bool)
    found = 0
    for _ in range(40):
        i, r = np.unravel_index(np.argmax(acc), acc.shape)
        if acc[i, r] < 150:
            break
        rho = r - rmax
        dist = np.abs(xs * ct[i] + ys * st[i] - rho)
        sel = (dist < 1.2) & ~used
        # refine the line direction by a least-squares fit of the selected pixels
        px, py = xs[sel].astype(float), ys[sel].astype(float)
        if len(px) < 120:
            acc[max(0, i - 8):i + 9, max(0, r - 6):r + 7] = 0; continue
        cx, cy = px.mean(), py.mean()
        u, s, vt = np.linalg.svd(np.stack([px - cx, py - cy], 1), full_matrices=False)
        dx, dy = vt[0]
        t = (px - cx) * dx + (py - cy) * dy
        ts = np.sort(t); br = np.nonzero(np.diff(ts) > 6)[0]
        st_ = np.concatenate([[0], br + 1]); en_ = np.concatenate([br, [len(ts) - 1]])
        used[np.nonzero(sel)[0]] = True
        acc[max(0, i - 8):i + 9, max(0, r - 6):r + 7] = 0
        for k in range(len(st_)):
            t0, t1 = ts[st_[k]], ts[en_[k]]
            x0, y0, x1, y1 = cx + t0 * dx, cy + t0 * dy, cx + t1 * dx, cy + t1 * dy
            L = np.hypot(x1 - x0, y1 - y0) / S
            if L >= 15:
                if (x0, y0) > (x1, y1):
                    x0, y0, x1, y1 = x1, y1, x0, y0
                print('%d	%.2f	%.2f	%.2f	%.2f	%.2f	%d	line%d' % (pn, x0 / S, y0 / S, x1 / S, y1 / S, L, int(((ts >= t0) & (ts <= t1)).sum()), found))
        found += 1
    if not found:
        print('%d\tNONE' % pn)
