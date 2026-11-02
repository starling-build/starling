#!/usr/bin/env python3
"""Lab fhang analyzer: usage analyze.py PDF-or-DIR > table. Page 1: top and bottom (bbox y0,y1) of INTRO, the label word "Note", AFTER one and AFTER two; plus the picture's top/bottom (image bbox) when there is one."""
import sys, os, glob, pymupdf
def main(a):
    files = sorted(glob.glob(os.path.join(a, "*.pdf"))) if os.path.isdir(a) else [a]
    print("doc\tintro_top\tnote_top\tnote_bottom\tpic_top\tpic_bottom\tafter1_top\tafter1_bottom\tafter2_top")
    for f in files:
        d = pymupdf.open(f); pg = d[0]; r = {}
        for b in pg.get_text("dict")["blocks"]:
            for l in b.get("lines", []):
                t = "".join(s["text"] for s in l["spans"])
                for k, key in (("INTRO", "intro"), ("Note", "note"), ("AFTER LINE one", "a1"), ("AFTER LINE two", "a2")):
                    if k in t and key not in r: r[key] = l["bbox"]
        imgs = [i["bbox"] for i in pg.get_image_info()]
        pic = imgs[0] if imgs else None
        g = lambda k, i: round(r[k][i], 1) if k in r else ""
        print(os.path.basename(f), g("intro", 1), g("note", 1), g("note", 3), round(pic[1], 1) if pic else "", round(pic[3], 1) if pic else "", g("a1", 1), g("a1", 3), g("a2", 1), sep="\t")
if __name__ == "__main__": main(sys.argv[1])
