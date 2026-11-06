#!/usr/bin/env python3
"""usage: analyze.py PDF  -> per table: x of the 'T' text and x0 of the leftmost drawn rect/line near it (pt)."""
import sys, pymupdf
d=pymupdf.open(sys.argv[1])
for pg in d:
    ts=[]
    for b in pg.get_text("dict")["blocks"]:
        for l in b.get("lines",[]):
            for s in l["spans"]:
                t=s["text"].strip()
                if t=="T": ts.append((l["bbox"][1],l["bbox"][0]))
                elif t.startswith("nest") or t.startswith("ind") or t.startswith("top") or t.startswith("bw") or t.startswith("cm"): print(" label",t[:40])
    dr=pg.get_drawings()
    for y,x in sorted(ts):
        xs=[r["rect"].x0 for r in dr if r["rect"].y0-3<=y<=r["rect"].y1+3 and r["rect"].width<400 and r["rect"].height<80]
        print(f"  T text x {x:.2f} y {y:.0f}  leftmost rect x0 {min(xs) if xs else None}")
