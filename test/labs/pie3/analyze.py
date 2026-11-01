#!/usr/bin/env python3
"""Lab pie3 analyzer: analyze.py PDF-or-DIR > table. One row per chart.
Columns: doc, id, share, rotX, rotY, pos, label_cx, label_cy, label_w, label_h, pie_x0, pie_y0, pie_x1, pie_y1, dx, dy
(dx, dy = label centre minus the centre of the pie's picture, points, y down). The pie picture is the page's raster (or, with no raster,
the union of the vector paths) that lies in the chart's half of the page."""
import sys, os, re, glob
try:
    import pymupdf as fitz
except ImportError:
    import fitz

def one(path):
    name = os.path.basename(path).replace(".pdf", "")
    for page in fitz.open(path):
        d = page.get_text("dict")
        lines = [(l["bbox"], "".join(s["text"] for s in l["spans"]).strip()) for b in d["blocks"] if "lines" in b for l in b["lines"]]
        heads = [(b[1], t) for b, t in lines if re.match(r"P\d{7} share=", t)]
        labels = {t: b for b, t in lines if re.fullmatch(r"P\d{7}", t)}
        imgs = [fitz.Rect(i["bbox"]) for i in page.get_image_info()]
        paths = [p["rect"] for p in page.get_drawings() if p["rect"].width > 20 and p["rect"].height > 20]
        for k, (hy, head) in enumerate(sorted(heads)):
            m = re.match(r"(P\d{7}) share=(\d+) rotX=(\d+) rotY=(\d+) pos=(\w+)", head)
            if not m: continue
            cid, share, rx, ry, pos = m.groups()
            top = hy; bot = sorted(heads)[k + 1][0] if k + 1 < len(heads) else 10000
            cand = [r for r in imgs if top <= r.y0 < bot] or [r for r in paths if top <= r.y0 < bot]
            if cand:
                u = fitz.Rect(cand[0])
                for r in cand[1:]: u |= r
            else:
                u = None
            lb = labels.get(cid)
            if lb is None or u is None:
                print("\t".join([name, cid, share, rx, ry, pos] + ["-"] * 10)); continue
            cx, cy = (lb[0] + lb[2]) / 2, (lb[1] + lb[3]) / 2
            px, py = (u.x0 + u.x1) / 2, (u.y0 + u.y1) / 2
            print("\t".join([name, cid, share, rx, ry, pos, f"{cx:.2f}", f"{cy:.2f}", f"{lb[2]-lb[0]:.2f}", f"{lb[3]-lb[1]:.2f}",
                             f"{u.x0:.2f}", f"{u.y0:.2f}", f"{u.x1:.2f}", f"{u.y1:.2f}", f"{cx-px:.2f}", f"{cy-py:.2f}"]))

for a in sys.argv[1:]:
    for p in (sorted(glob.glob(os.path.join(a, "*.pdf"))) if os.path.isdir(a) else [a]):
        one(p)
