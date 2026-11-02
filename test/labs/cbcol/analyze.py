#!/usr/bin/env python3
"""Lab cbcol analyzer: usage analyze.py PDF-or-DIR > table. Page 1: the x of every vertical table border (column edges, left to right), and the x of the left edge of the first word in each of the other three columns."""
import sys, os, glob, pymupdf
def main(a):
    files = sorted(glob.glob(os.path.join(a, "*.pdf"))) if os.path.isdir(a) else [a]
    print("doc\tedges_x...")
    for f in files:
        pg = pymupdf.open(f)[0]; xs = set()
        for d in pg.get_drawings():
            for it in d["items"]:
                if it[0] == "l" and abs(it[1].x - it[2].x) < 0.2 and abs(it[1].y - it[2].y) > 5: xs.add(round(it[1].x, 1))
                if it[0] == "re":
                    r = it[1]
                    if r.width < 1.5 and r.height > 5: xs.add(round((r.x0 + r.x1) / 2, 1))
        print(os.path.basename(f), *sorted(xs), sep="\t")
if __name__ == "__main__": main(sys.argv[1])
