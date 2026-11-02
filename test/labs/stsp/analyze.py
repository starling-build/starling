#!/usr/bin/env python3
"""Lab stsp analyzer: usage analyze.py PDF-or-DIR > table. Page 1: doc, then the top (bbox y0) and baseline-ish bottom (y1) of each "BODY LINE n"."""
import sys, os, glob, pymupdf
def main(a):
    files = sorted(glob.glob(os.path.join(a, "*.pdf"))) if os.path.isdir(a) else [a]
    print("doc\tline1_top\tline1_bottom\tline2_top\tline3_top\tline4_top")
    for f in files:
        d = pymupdf.open(f); rows = {}
        for b in d[0].get_text("dict")["blocks"]:
            for l in b.get("lines", []):
                t = "".join(s["text"] for s in l["spans"])
                if "BODY LINE" in t: rows[int(t.split()[-1])] = l["bbox"]
        print(os.path.basename(f), round(rows[1][1], 1), round(rows[1][3], 1), *[round(rows[k][1], 1) for k in (2, 3, 4)], sep="\t")
if __name__ == "__main__": main(sys.argv[1])
