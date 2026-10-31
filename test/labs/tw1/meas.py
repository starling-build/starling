# meas.py PDF... — lab tw1: per print, the x of every vertical rule of the table (its column edges, per row band) and the x of
# each cell's text (A1 B1 C1 D1), so the column widths and the table's left edge can be read off.
import sys, pymupdf
for f in sorted(sys.argv[1:]):
    pg = pymupdf.open(f)[0]
    print("==", f.split("/")[-1])
    rules = []
    for d in pg.get_drawings():
        for it in d["items"]:
            if it[0] == "l":
                a, b = it[1], it[2]
                if abs(a.x - b.x) < 0.5 and abs(a.y - b.y) > 5: rules.append((round(a.y, 1), round(a.x, 1)))
            elif it[0] == "re":
                r = it[1]
                if r.width < 1.5 and r.height > 5: rules.append((round(r.y0, 1), round(r.x0, 1)))
    bands = {}
    for y, x in rules: bands.setdefault(y, set()).add(x)
    for y in sorted(bands): print("  rules from y %6.1f: x = %s" % (y, " ".join("%.1f" % x for x in sorted(bands[y]))))
    for b in pg.get_text("dict")["blocks"]:
        for l in b.get("lines", []):
            t = "".join(s["text"] for s in l["spans"]).strip()
            if t: print("  text %-6s x %6.1f  y %6.1f  right %6.1f" % (t, l["bbox"][0], l["bbox"][1], l["bbox"][2]))
