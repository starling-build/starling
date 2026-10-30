# meas.py PDF... — lab frame: per print, the union of the drawn shapes' boxes on page 1 (x0 y0 x1 y1, page coordinates in points), the
# count of shapes, and every text line as "y x text". Word's print of the original (v00) is at [70.8, 22.8, 207.3, 111.2], 32 glyph lines.
import sys, pymupdf
for f in sorted(sys.argv[1:]):
    pg = pymupdf.open(f)[0]
    ds = [d["rect"] for d in pg.get_drawings() if d["rect"].width > 1]
    print("==", f.split("/")[-1], "pages", len(pymupdf.open(f)))
    if ds:
        r = pymupdf.Rect(ds[0])
        for x in ds: r |= x
        print("  shapes %d  union x0 %.1f  y0 %.1f  x1 %.1f  y1 %.1f   (w %.1f  h %.1f)" % (len(ds), r.x0, r.y0, r.x1, r.y1, r.width, r.height))
    n = 0
    for b in pg.get_text("rawdict")["blocks"]:
        for l in b.get("lines", []):
            t = "".join(c["c"] for s in l["spans"] for c in s["chars"])
            if t.strip() and n < 6:
                print("  text y %.1f x %.1f %s" % (l["bbox"][1], l["bbox"][0], t[:30])); n += 1
