#!/usr/bin/env python3
"""Lab vm2 analyzer: analyze.py PDF-or-DIR > table. One row per page (= one table).
Columns: doc, page, label, table_top_pt, table_bottom_pt, height_pt, first_cell_text_top_minus_table_top_pt, marker_top_minus_table_bottom_pt"""
import sys, os, glob
try:
    import pymupdf as fitz
except ImportError:
    import fitz

def one(path):
    name = os.path.basename(path).replace(".pdf", "")
    doc = fitz.open(path)
    for i, page in enumerate(doc, 1):
        lines = [(round(l["bbox"][1], 2), "".join(s["text"] for s in l["spans"])) for b in page.get_text("dict")["blocks"] if "lines" in b for l in b["lines"]]
        label = next((t for y, t in lines if t.startswith("T") and " " in t), "?")
        rules = [r for r in page.get_drawings() for r in [r["rect"]] if r.width > 100 and r.height < 3]
        if not rules:
            print(f"{name}\t{i}\t{label}\t-\t-\t-\t-\t-"); continue
        top = min(r.y0 for r in rules); bot = max(r.y1 for r in rules)
        cell = next((y for y, t in lines if t.startswith("类")), None)
        mark = next((y for y, t in lines if t.startswith("==")), None)
        print("\t".join([name, str(i), label, f"{top:.2f}", f"{bot:.2f}", f"{bot-top:.2f}",
                         "-" if cell is None else f"{cell-top:.2f}", "-" if mark is None else f"{mark-bot:.2f}"]))

for a in sys.argv[1:]:
    for p in (sorted(glob.glob(os.path.join(a, "*.pdf"))) if os.path.isdir(a) else [a]):
        one(p)
