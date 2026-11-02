#!/usr/bin/env python3
"""meas.py PDF [PDF...] — per variant, per paragraph (T = -1.0 + 0.2*k pt over): does the first line end with the digit?"""
import sys, pymupdf
for f in sys.argv[1:]:
    D = pymupdf.open(f)
    lines = []
    for p in D:
        for b in p.get_text("dict")["blocks"]:
            for l in b.get("lines", []):
                lines.append("".join(sp["text"] for sp in l["spans"]))
    firsts = [t for t in lines if t.startswith("（一）住宅建筑")]
    print(f.split('/')[-1], len(firsts))
    for k, t in enumerate(firsts):
        t = t.rstrip()
        print("  T=%.1f" % (-1.0 + 0.2 * k), "TAKEN" if t.endswith("4") else "down ", t[-5:])
