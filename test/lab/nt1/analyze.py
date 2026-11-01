#!/usr/bin/env python3
"""analyze.py DIR > table: per document and page: number of 'Line NN' lines, first and last line (baseline, bottom = y1), and the y of every horizontal rule (table borders), pt from the page top."""
import sys, glob, os, re, pymupdf
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*-orig.pdf"))):
    d = pymupdf.open(f)
    print("##", os.path.basename(f)[:-9], "pages", len(d))
    for pno, p in enumerate(d):
        L = []
        for b in p.get_text("dict")["blocks"]:
            for l in b.get("lines", []):
                t = "".join(s["text"] for s in l["spans"]).strip()
                m = re.match(r"Line (\d\d)", t)
                if m:
                    L.append((int(m.group(1)), l["spans"][0]["origin"][1], l["bbox"][3]))
        L.sort()
        rules = sorted({round(dr["rect"].y0, 2) for dr in p.get_drawings() if dr["rect"].width > 300 and dr["rect"].height < 3})
        if L:
            print(f"p{pno+1}\tlines {len(L)}\tfirst Line {L[0][0]:02d} base {L[0][1]:.2f} y1 {L[0][2]:.2f}\tlast Line {L[-1][0]:02d} base {L[-1][1]:.2f} y1 {L[-1][2]:.2f}\trules {rules}")
        else:
            print(f"p{pno+1}\tno Line text\trules {rules}")
