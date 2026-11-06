#!/usr/bin/env python3
"""usage: analyze.py PDF-or-DIR > table. Per page-1 PDF: the top y of the empty box (the 102x33pt rectangle) and the chart frame's top/bottom y. Needs pymupdf."""
import sys, os, pymupdf
def one(path):
    page = pymupdf.open(path)[0]
    box = chart = None
    for dr in page.get_drawings():
        r = dr["rect"]
        if abs(r.width - 102) < 3 and abs(r.height - 33) < 3 and box is None: box = r
        elif r.width > 300 and r.height > 200 and chart is None: chart = r
    f = lambda r, a: "-" if r is None else f"{getattr(r, a):.1f}"
    return (os.path.basename(path), f(box, "y0"), f(chart, "y0"), f(chart, "y1"))
args = sys.argv[1:]
fs = [os.path.join(a, f) for a in args if os.path.isdir(a) for f in sorted(os.listdir(a)) if f.endswith(".pdf")] + [a for a in args if a.endswith(".pdf")]
print("doc\tbox_top\tchart_top\tchart_bottom")
for f in fs: print("\t".join(one(f)))
