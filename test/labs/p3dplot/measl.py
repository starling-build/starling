# measl.py PDF... — chart 1 (page 3): every label's box (its lines joined by
# category name: the name line, then the value and percent lines under it) and
# the pie's coloured extent (meas.py's blob union).
import sys, pymupdf
sys.path.insert(0, __import__("os").path.dirname(__file__))
from meas import blob
NAMES = ["經濟", "科技", "文化", "教育", "金融", "建築"]
for f in sys.argv[1:]:
    pg = pymupdf.open(f)[2]
    lines = []
    for b in pg.get_text("dict")["blocks"]:
        for l in b.get("lines", []):
            t = "".join(s["text"] for s in l["spans"]).strip()
            x0, y0, x1, y1 = l["bbox"]
            if 95 < y0 < 320: lines.append((t, x0, y0, x1, y1))
    out = []
    for nm in NAMES:
        for (t, x0, y0, x1, y1) in lines:
            if t == nm:
                below = [L for L in lines if L[0] != nm and abs((L[1] + L[3]) / 2 - (x0 + x1) / 2) < 8 and 0 < L[2] - y0 < 30]
                yb = max([y1] + [L[4] for L in below])
                xs = [x0, x1] + [v for L in below for v in (L[1], L[3])]
                out.append("%s (%.1f,%.1f)" % (nm, (min(xs) + max(xs)) / 2, (y0 + yb) / 2))
                break
        else: out.append(nm + " -")
    p = blob(pg, pymupdf.Rect(100, 95, 505, 320))
    print("%-16s pie %s | %s" % (f.split("/")[-1][:16], "-" if not p else "(%.1f,%.1f)-(%.1f,%.1f)" % tuple(p), "  ".join(out)))
