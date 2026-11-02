#!/usr/bin/env python3
"""Lab bal analyzer: usage analyze.py PDF-or-DIR > table. Per document, page 1: every text line as 'x0 y0 y1 size text', body lines (x0 < 400) and balloon lines (x0 >= 400) in two lists, by y."""
import sys, os, glob, pymupdf
def main(a):
    files = sorted(glob.glob(os.path.join(a, "*.pdf"))) if os.path.isdir(a) else [a]
    for f in files:
        pg = pymupdf.open(f)[0]; rows = []
        for b in pg.get_text("dict")["blocks"]:
            for l in b.get("lines", []):
                t = "".join(s["text"] for s in l["spans"]).strip()
                if t: rows.append((round(l["bbox"][1], 1), round(l["bbox"][0], 1), round(l["bbox"][3], 1), round(l["spans"][0]["size"], 1), t))
        print("##", os.path.basename(f), "page width", round(pg.rect.width, 1))
        for y0, x0, y1, sz, t in sorted(rows): print(f"{'B' if x0 >= 400 else 'T'}\t{x0}\t{y0}\t{y1}\t{sz}\t{t}")
if __name__ == "__main__": main(sys.argv[1])
