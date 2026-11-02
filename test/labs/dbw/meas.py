#!/usr/bin/env python3
"""meas.py PDF [PDF...] — per variant, per paragraph (T = 1.0 + 0.2*k pt over): does the first line end with the piece?"""
import sys, pymupdf
for f in sys.argv[1:]:
    D = pymupdf.open(f)
    lines = []
    for p in D:
        for b in p.get_text("dict")["blocks"]:
            for l in b.get("lines", []):
                lines.append("".join(sp["text"] for sp in l["spans"]))
    firsts = [t for t in lines if "以下重复列出了" in t]
    print(f.split('/')[-1], len(firsts))
    for k, t in enumerate(firsts):
        print("  T=%.1f" % (1.0 + 0.2 * k), "TAKEN" if t.rstrip().endswith(("DB", "库")) else "down ", t[-6:])
