#!/usr/bin/env python3
"""usage: analyze.py PDF-or-DIR > table. Per paragraph: tag, the first line's text, and its last 6 characters. Needs pymupdf."""
import sys, os, re, fitz
def one(path):
    rows = []
    for page in fitz.open(path):
        lines = []
        for b in page.get_text("dict")["blocks"]:
            for l in b.get("lines", []):
                t = "".join(s["text"] for s in l["spans"])
                lines.append((round(l["bbox"][1], 1), l["bbox"][0], t))
        lines.sort()
        cur = None
        for y, x, t in lines:
            m = re.match(r"([ADCHN]-\d\d-\d)\s+\[", t)
            if m: cur = m.group(1); first = True; continue
            if cur and first:
                rows.append((os.path.basename(path), cur, t, t[-6:])); first = False
    return rows
args = sys.argv[1:]
files = [os.path.join(a, f) for a in args if os.path.isdir(a) for f in sorted(os.listdir(a)) if f.endswith(".pdf")] + [a for a in args if a.endswith(".pdf")]
for f in files:
    for r in one(f): print("\t".join(r))
