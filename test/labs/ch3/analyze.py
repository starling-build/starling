#!/usr/bin/env python3
"""analyze.py PDF > table. Per page (variant): every text span of the chart (text, right edge x1, left x0, centre x, baseline y), in pt from the chart frame's top-left
(page margin 36pt, label line 12pt exact => frame top-left = (36, 48)), then the filled rectangles/polygons (fill colour, bbox) of the plot."""
import sys, pymupdf
FX, FY = 36.0, 48.0
d = pymupdf.open(sys.argv[1])
for pno, p in enumerate(d):
    label = ""
    print(f"## page {pno+1}")
    for b in p.get_text("dict")["blocks"]:
        for l in b.get("lines", []):
            for s in l["spans"]:
                t = s["text"].strip()
                if not t:
                    continue
                x0, y0, x1, y1 = s["bbox"]
                ox, oy = s["origin"]
                if pno >= 0 and oy < FY - 2 and not label:
                    label = t
                    print("variant", t)
                    continue
                print(f"T\t{t}\tx0={x0-FX:.2f}\tx1={x1-FX:.2f}\tcx={(x0+x1)/2-FX:.2f}\tbase={oy-FY:.2f}\tsize={s['size']:.1f}")
    fills = []
    for dr in p.get_drawings():
        f = dr.get("fill")
        r = dr["rect"]
        if f is None or r.width < 0.5 and r.height < 0.5:
            continue
        fills.append((tuple(round(c, 2) for c in f), round(r.x0 - FX, 2), round(r.y0 - FY, 2), round(r.x1 - FX, 2), round(r.y1 - FY, 2)))
    for f in fills:
        print("F\t%s\tx0=%.2f\ty0=%.2f\tx1=%.2f\ty1=%.2f" % (f[0], f[1], f[2], f[3], f[4]))
