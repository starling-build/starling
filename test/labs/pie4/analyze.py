#!/usr/bin/env python3
"""Lab pie4 analyzer: analyze.py PDF-or-DIR > table. One row per chart.
Columns: doc, id, fam, share, rotX, rotY, pos, persp, expl, size, label_cx, label_cy, label_w, label_h (the label's whole text block, so a
wrapped label is one box), pie_x0, pie_y0, pie_x1, pie_y1 (the raster Word draws, or the union of its paths, in the chart's half of the page),
dx, dy = label centre minus that box's centre. Needs PyMuPDF."""
import sys, os, re, glob
try: import pymupdf as fitz
except ImportError: import fitz

def one(path):
    name = os.path.basename(path).replace(".pdf", "")
    for page in fitz.open(path):
        d = page.get_text("dict")
        blocks = [b for b in d["blocks"] if "lines" in b]
        def text(b): return " ".join("".join(s["text"] for s in l["spans"]).strip() for l in b["lines"])
        heads = []
        for b in blocks:
            t = text(b); m = re.match(r"Q(\d{4}) fam=(\w) share=(\d+) rotX=(\d+) rotY=(\d+) pos=(\w+) persp=(\d+) expl=(\S+) size=(\S+)", t)
            if m: heads.append((b["bbox"][1], m.groups()))
        heads.sort()
        imgs = [fitz.Rect(i["bbox"]) for i in page.get_image_info()]
        paths = [p["rect"] for p in page.get_drawings() if p["rect"].width > 20 and p["rect"].height > 20]
        for k, (hy, g) in enumerate(heads):
            cid = g[0]; bot = heads[k + 1][0] if k + 1 < len(heads) else 10000
            # the label: every text block of the chart's half of the page that is not a heading and not the (deleted) second category
            lab = [b for b in blocks if hy + 6 <= b["bbox"][1] < bot and not re.match(r"Q\d{4} fam=", text(b)) and text(b).strip() != "rest"]
            cand = [r for r in imgs if hy <= r.y0 < bot] or [r for r in paths if hy <= r.y0 < bot]
            if not lab or not cand:
                print("\t".join([name, f"Q{cid}"] + list(g[1:]) + ["-"] * 10)); continue
            u = fitz.Rect(cand[0])
            for r in cand[1:]: u |= r
            b = fitz.Rect(lab[0]["bbox"])
            for x in lab[1:]: b |= fitz.Rect(x["bbox"])
            cx, cy = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2; px, py = (u.x0 + u.x1) / 2, (u.y0 + u.y1) / 2
            print("\t".join([name, f"Q{cid}", g[1], g[2], g[3], g[4], g[5], g[6], g[7], g[8],
                             f"{cx:.2f}", f"{cy:.2f}", f"{b[2]-b[0]:.2f}", f"{b[3]-b[1]:.2f}",
                             f"{u.x0:.2f}", f"{u.y0:.2f}", f"{u.x1:.2f}", f"{u.y1:.2f}", f"{cx-px:.2f}", f"{cy-py:.2f}"]))

for a in sys.argv[1:]:
    for p in (sorted(glob.glob(os.path.join(a, "*.pdf"))) if os.path.isdir(a) else [a]):
        one(p)
