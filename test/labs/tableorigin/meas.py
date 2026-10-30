#!/usr/bin/env python3
"""meas.py DIR — for each PDF in DIR (the prints of test/labs/tableorigin/docx): x of the table's leftmost and
rightmost vertical rule (0.01pt) and the x of the letters A..D.  Needs PyMuPDF."""
import glob, os, sys
import pymupdf
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*.pdf"))):
    d = pymupdf.open(f); p = d[0]; xs = []
    for r in p.get_drawings():
        R = r["rect"]
        if R.width < 2 and R.height > 5: xs.append((R.x0 + R.x1) / 2)
        for it in r["items"]:
            if it[0] == "l" and abs(it[1].x - it[2].x) < 0.01 and abs(it[1].y - it[2].y) > 5: xs.append(it[1].x)
    letters = {}
    for w in p.get_text("words"):
        if w[4] in ("A", "B", "C", "D"): letters[w[4]] = round(w[0], 2)
    print(f"{os.path.basename(f):30s} rules {round(min(xs),2) if xs else None} .. {round(max(xs),2) if xs else None}  letters {letters}")
