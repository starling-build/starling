# meas.py PDF... — each print's first two lines: text, and the first line's right end.
import sys, pymupdf
for f in sorted(sys.argv[1:]):
    pg = pymupdf.open(f)[0]; L = []
    for b in pg.get_text("dict")["blocks"]:
        for l in b.get("lines", []):
            t = "".join(s["text"] for s in l["spans"]).replace(" ", "")
            if t: L.append((l["bbox"][1], l["bbox"][2], t))
    L.sort()
    a = L[0] if L else (0, 0, ""); nxt = L[1][2] if len(L) > 1 else ""
    print("%-22s end %6.1f  …%s | next: %s" % (f.split("/")[-1][:22], a[1], a[2][-8:], nxt[:8]))
