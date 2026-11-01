#!/usr/bin/env python3
"""Lab cb2 analyzer: analyze.py PDF-or-DIR > table. One row per page (= one variant V1..V8).
Columns: doc, page, variant, A_top_pt, B_top_pt, B_left_pt, B_page (page the B line is on), dy = B_top - A_top (0 if B is on the same page's second column at the same height as A)"""
import sys, os, glob
try:
    import pymupdf as fitz
except ImportError:
    import fitz
def one(path):
    name = os.path.basename(path).replace(".pdf", "")
    doc = fitz.open(path)
    for i, page in enumerate(doc, 1):
        L = [(l["bbox"][1], l["bbox"][0], "".join(s["text"] for s in l["spans"])) for b in page.get_text("dict")["blocks"] if "lines" in b for l in b["lines"]]
        a = next(((y, x, t) for y, x, t in L if t.startswith("AW")), None)
        b = next(((y, x, t) for y, x, t in L if t.startswith("BW")), None)
        if not a or not b:
            print(f"{name}\t{i}\t{(a or b or ('','',''))[2]}\t-\t-\t-\t-"); continue
        print("\t".join([name, str(i), a[2][1:], f"{a[0]:.2f}", f"{b[0]:.2f}", f"{b[1]:.2f}", f"{b[0]-a[0]:.2f}"]))
for a in sys.argv[1:]:
    for p in (sorted(glob.glob(os.path.join(a, "*.pdf"))) if os.path.isdir(a) else [a]):
        one(p)
