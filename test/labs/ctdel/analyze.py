#!/usr/bin/env python3
"""Lab ctdel analyzer: usage analyze.py PDF-or-DIR > table. For each print: the balloon column's lines (x > 400 on the
scaled page): first-line left x, widest right x, line count, and the text of each line. Compare D2..D12 with D1."""
import sys, os, glob, pymupdf
def lines(pdf):
    d = pymupdf.open(pdf); out = []
    for pg in d[:1]:
        for b in pg.get_text("dict")["blocks"]:
            for l in b.get("lines", []):
                for s in l["spans"]:
                    if s["bbox"][0] > 400 and s["text"].strip():
                        out.append((round(l["bbox"][1], 1), round(s["bbox"][0], 1), round(s["bbox"][2], 1), s["text"]))
    return sorted(out)
def main(a):
    files = sorted(glob.glob(os.path.join(a, "*.pdf"))) if os.path.isdir(a) else [a]
    print("doc\tballoon_lines\tleft_x\tright_x_max\ttext of first line")
    for f in files:
        ls = lines(f)
        if not ls: print(os.path.basename(f), "no balloon text", sep="\t"); continue
        print(os.path.basename(f), len(ls), min(l[1] for l in ls), max(l[2] for l in ls), ls[0][3][:40], sep="\t")
if __name__ == "__main__":
    main(sys.argv[1])
