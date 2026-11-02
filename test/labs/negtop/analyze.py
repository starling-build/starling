#!/usr/bin/env python3
"""Lab negtop analyzer: usage analyze.py PDF-or-DIR > table. Page 1 only: doc, then 'HEADER y' (top of the header text's box), 'BODY1 y' (top of "BODY LINE 1"), line count of BODY."""
import sys, os, glob, pymupdf
def main(a):
    files = sorted(glob.glob(os.path.join(a, "*.pdf"))) if os.path.isdir(a) else [a]
    print("doc\theader_top\tbody1_top\tbody_lines_on_page1\tpages")
    for f in files:
        d = pymupdf.open(f); h = b1 = None; nb = 0
        for b in d[0].get_text("dict")["blocks"]:
            for l in b.get("lines", []):
                t = "".join(s["text"] for s in l["spans"])
                if "HEADER" in t and h is None: h = round(l["bbox"][1], 1)
                if "BODY LINE" in t:
                    nb += 1
                    if "LINE 1" in t: b1 = round(l["bbox"][1], 1)
        print(os.path.basename(f), h, b1, nb, len(d), sep="\t")
if __name__ == "__main__":
    main(sys.argv[1])
