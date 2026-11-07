#!/usr/bin/env python3
"""wall.py DIR > BAR3DLEFT-WORD.tsv (Windows 01QbbApP, for amd-1). Per b3l-*-orig.pdf (the 3-D chart is ONE raster image; the labels are text):
kind=img: bbox x0 y0 x1 y1 (pt) and px size; kind=grid: each long horizontal grey (~215) gridline of the back wall: y centre, x0, x1 (pt);
kind=leftdiag: for each gridline, the leftmost grey pixel x in the band just below/left of it (the left wall's slanted edge, pt) ; kind=tick: value-axis labels (x0,x1,ymid);
kind=cat: category labels; kind=frame: the chart frame rect. All pt on the page, from the page top-left."""
import sys, os, re, pymupdf
print('# doc\tkind\ta\tb\tc\td\te')
for f in sorted(x for x in os.listdir(sys.argv[1]) if x.endswith('-orig.pdf')):
    d = pymupdf.open(os.path.join(sys.argv[1], f)); p = d[0]; n = f[:-9]
    for dr in p.get_drawings():
        if dr.get('color') == (0.0, 0.0, 0.0) and not dr.get('fill') and dr['rect'].width > 300:
            print('%s\tframe\t%.2f\t%.2f\t%.2f\t%.2f\t' % (n, *dr['rect'])); break
    ii = p.get_image_info(xrefs=True)
    if not ii: print(n + '\timg\tnone'); continue
    im = ii[0]; pm = pymupdf.Pixmap(d, im['xref']); b = im['bbox']; sx = pm.width / (b[2] - b[0]); sy = pm.height / (b[3] - b[1])
    print('%s\timg\t%.2f\t%.2f\t%.2f\t%.2f\t%dx%d' % (n, *b, pm.width, pm.height))
    samp = pm.samples; W = pm.width; H = pm.height; N = pm.n
    def grey(x, y):
        o = (y * W + x) * N; r, g, bb = samp[o], samp[o + 1], samp[o + 2]
        return 200 <= r <= 232 and abs(r - g) <= 3 and abs(r - bb) <= 3
    rows = []
    for y in range(H):
        best = (0, 0, 0); s = None
        for x in range(W + 1):
            g = x < W and grey(x, y)
            if g and s is None: s = x
            if not g and s is not None:
                if x - s > best[0]: best = (x - s, s, x)
                s = None
        if best[0] >= 150: rows.append((y, best[1], best[2]))
    # merge adjacent rows
    groups = []
    for r in rows:
        if groups and r[0] - groups[-1][-1][0] <= 2: groups[-1].append(r)
        else: groups.append([r])
    first_x0 = (b[0] + groups[0][0][1] / sx) if groups else None
    for g in groups:
        y = sum(r[0] for r in g) / len(g) + 0.5; x0 = min(r[1] for r in g); x1 = max(r[2] for r in g)
        # slanted left-wall edge: leftmost grey pixel within 60 px left/below this row
        lm = None
        for yy in range(int(y), min(H, int(y) + 60)):
            for x in range(0, x0):
                if grey(x, yy): lm = x if lm is None else min(lm, x); break
        print('%s\tgrid\t%.2f\t%.2f\t%.2f\t%.2f\t' % (n, b[1] + y / sy, b[0] + x0 / sx, b[0] + x1 / sx, (b[0] + lm / sx) if lm is not None else float('nan')))
    for w in p.get_text('words'):
        if re.fullmatch(r'[\d,.\-]+', w[4]) and w[2] <= (first_x0 if first_x0 else b[0] + 80) + 0.5 and w[0] < b[0] + 80:
            print('%s\ttick\t%.2f\t%.2f\t%.2f\t%s\t' % (n, w[0], w[2], (w[1] + w[3]) / 2, w[4]))
        elif re.search(r'[一-鿿]', w[4]) and w[1] > b[1] + 220 and w[1] < b[1] + 290:
            print('%s\tcat\t%.2f\t%.2f\t%.2f\t%s\t' % (n, w[0], w[2], (w[1] + w[3]) / 2, w[4]))
