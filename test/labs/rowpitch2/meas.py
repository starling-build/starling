#!/usr/bin/env python3
"""meas.py DIR — for each PDF in DIR (the prints of test/labs/rowpitch2/docx), the baseline y of every "x"
glyph, the mean pitch of consecutive rows (0.001pt), the spread and the running total.  Needs PyMuPDF."""
import glob, os, sys
import pymupdf
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.pdf"))):
    d = pymupdf.open(f); ys = []
    for p in d:
        for b in p.get_text("rawdict")["blocks"]:
            for l in b.get("lines", []):
                for s in l["spans"]:
                    ys += [c["origin"][1] for c in s["chars"] if c["c"] == "x"]
    ys.sort()
    if len(ys) < 2: print(os.path.basename(f), "no rows"); continue
    st = [b - a for a, b in zip(ys, ys[1:])]
    print(f"{os.path.basename(f):28s} rows {len(ys):3d}  mean pitch {sum(st)/len(st):.3f}  spread {max(st)-min(st):.3f}  total {ys[-1]-ys[0]:.3f}  first {ys[0]:.3f}")
