#!/usr/bin/env python3
"""bars.py PDF -- the plot is a bitmap in Word's print: per page the image's placement (pt from the frame TL) and, per series colour, the x-runs (bar front faces) with top/bottom y."""
import sys, pymupdf
FX, FY = 36.0, 48.0
d = pymupdf.open(sys.argv[1])
COLS = {"S1teal": (21, 96, 130), "S2orange": (233, 113, 50)}
for pno, p in enumerate(d):
    for info in p.get_image_info(xrefs=True):
        r = pymupdf.Rect(info["bbox"])
        if r.width < 100: continue
        pix = pymupdf.Pixmap(d, info["xref"])
        if pix.alpha: pix = pymupdf.Pixmap(pix, 0)
        W, H = pix.width, pix.height
        sx, sy = r.width / W, r.height / H
        print(f"## page {pno+1} image at x0={r.x0-FX:.2f} y0={r.y0-FY:.2f} x1={r.x1-FX:.2f} y1={r.y1-FY:.2f} px={W}x{H} ({1/sx:.2f} px/pt)")
        s = pix.samples; n = pix.n
        for nm, (R, G, B) in COLS.items():
            cols = {}
            for y in range(H):
                row = y * W * n
                for x in range(W):
                    o = row + x * n
                    if abs(s[o] - R) < 12 and abs(s[o+1] - G) < 12 and abs(s[o+2] - B) < 12:
                        c = cols.setdefault(x, [y, y]); c[1] = y
            xs = sorted(cols); runs = []
            for x in xs:
                if runs and x - runs[-1][1] <= 1: runs[-1][1] = x
                else: runs.append([x, x])
            for a, b in runs:
                if b - a < 3: continue
                top = min(cols[x][0] for x in range(a, b + 1)); bot = max(cols[x][1] for x in range(a, b + 1))
                print(f"B\t{nm}\tx0={r.x0-FX+a*sx:.2f}\tx1={r.x0-FX+(b+1)*sx:.2f}\ttop={r.y0-FY+top*sy:.2f}\tbottom={r.y0-FY+(bot+1)*sy:.2f}")
