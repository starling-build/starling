#!/usr/bin/env python3
"""Lab ovfit analyzer: usage analyze.py PDF-or-DIR > table. Page 1: for each document the left x of the words c1, c2, ... (cell text starts) and the line count of the first row."""
import sys, os, glob, re, pymupdf
def main(a):
    files = sorted(glob.glob(os.path.join(a, "*.pdf"))) if os.path.isdir(a) else [a]
    print("doc\tc_left_x...\tlines_in_widest_cell")
    for f in files:
        d = pymupdf.open(f); xs = {}; ys = set()
        for w in d[0].get_text("words"):
            m = re.fullmatch(r"c(\d)", w[4])
            if m: xs[int(m.group(1))] = round(w[0], 1)
            if w[1] > 0: ys.add(round(w[1], 0))
        print(os.path.basename(f), *[xs.get(k) for k in sorted(xs)], len(ys), sep="\t")
if __name__ == "__main__": main(sys.argv[1])
