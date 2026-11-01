#!/usr/bin/env python3
"""analyze.py DIR-or-PDFs > table: per document and page, every text line (top y0, baseline y, first 14 chars), y in pt from the page top."""
import sys, glob, os, pymupdf
args = sys.argv[1:]
files = sorted(glob.glob(os.path.join(args[0], "*-orig.pdf"))) if len(args) == 1 and os.path.isdir(args[0]) else args
for f in files:
    d = pymupdf.open(f)
    print("##", os.path.basename(f)[:-9], "pages", len(d), "height", round(d[0].rect.height, 1))
    for pno, p in enumerate(d):
        for b in p.get_text("dict")["blocks"]:
            for l in b.get("lines", []):
                t = "".join(s["text"] for s in l["spans"]).strip()
                if t:
                    print(f"p{pno+1}\ty0={l['bbox'][1]:.2f}\tbase={l['spans'][0]['origin'][1]:.2f}\t{t[:14]}")
