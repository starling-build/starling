# meas.py PDF... — per print: every text span on the page's foot (y > 700): text, size, x0, x1, y0.
import sys, pymupdf
for f in sorted(sys.argv[1:]):
    d = pymupdf.open(f)
    for pn, pg in enumerate(d):
        for b in pg.get_text("dict")["blocks"]:
            for l in b.get("lines", []):
                for s in l["spans"]:
                    if l["bbox"][1] > 700 and s["text"].strip():
                        print("%-14s p%d %-10r size %5.2f x %6.1f-%6.1f y %6.1f" % (f.split("/")[-1][:14], pn + 1, s["text"], s["size"], l["bbox"][0], l["bbox"][2], l["bbox"][1]))
