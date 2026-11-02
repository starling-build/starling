#!/usr/bin/env python3
"""measure.py DIR_OF_PDFS — for each pie-*.pdf: the large slice's bounding box (pie centre, radius) and
each label's text box centre relative to the pie centre, in points. Needs PyMuPDF."""
import sys, os, math, pymupdf
for f in sorted(os.listdir(sys.argv[1])):
    if not f.endswith(".pdf"): continue
    page = pymupdf.open(os.path.join(sys.argv[1], f))[0]
    boxes = [d["rect"] for d in page.get_drawings() if d.get("fill") and 60 < d["rect"].width < 130 and abs(d["rect"].width - d["rect"].height) < 4]
    if not boxes: print(f, "no pie found"); continue
    r = max(boxes, key=lambda b: b.width)
    cx, cy, R = (r.x0 + r.x1) / 2, (r.y0 + r.y1) / 2, r.width / 2
    out = []
    for b in page.get_text("dict")["blocks"]:
        for l in b.get("lines", []):
            t = "".join(s["text"] for s in l["spans"])
            bx = pymupdf.Rect(l["bbox"])
            if abs((bx.x0+bx.x1)/2 - cx) < R * 1.3 and abs((bx.y0+bx.y1)/2 - cy) < R * 1.3 and "Table" not in t:
                out.append(f"{t!r} centre ({(bx.x0+bx.x1)/2-cx:+.1f},{(bx.y0+bx.y1)/2-cy:+.1f}) size {bx.width:.1f}x{bx.height:.1f}")
    print(f, f"pie centre ({cx:.1f},{cy:.1f}) R {R:.1f}", "; ".join(out))
