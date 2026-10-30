# meas.py PDF... — each print: the first line's right end, its last 8 characters, and the next line's first 8
# (whether the piece was taken: the piece stands at the end of line 1 or opens line 2).
import sys, pymupdf
for f in sorted(sys.argv[1:]):
    pg = pymupdf.open(f)[0]; L = []
    for b in pg.get_text("dict")["blocks"]:
        for l in b.get("lines", []):
            t = "".join(s["text"] for s in l["spans"]).replace(" ", "")
            if t: L.append((round(l["bbox"][1]), l["bbox"][2], t))
    L.sort()
    a = L[0] if L else (0, 0, ""); nxt = L[1][2] if len(L) > 1 else ""
    print("%-16s end %6.1f  …%s | next: %s" % (f.split("/")[-1][:16], a[1], a[2][-8:], nxt[:8]))
