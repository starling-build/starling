# meas.py PDF... — chart 1's (page 3) and chart 2's pie: the coloured pixels'
# largest connected blob (so legend swatches and label text drop out),
# the union of its coloured blobs over 1500 px at 2x (slices are split by white
# borders; legend swatches and label text drop out): its top, bottom, left, right and centre in points.
import sys, pymupdf
from PIL import Image
def blob(pg, clip, z=2):
    pix = pg.get_pixmap(matrix=pymupdf.Matrix(z, z), clip=clip)
    im = Image.frombytes("RGB", (pix.width, pix.height), pix.samples).load()
    W, H = pix.width, pix.height
    on = [[max(im[x, y]) - min(im[x, y]) > 60 for x in range(W)] for y in range(H)]
    seen = [[False] * W for _ in range(H)]; best = None; U = None
    for y0 in range(H):
        for x0 in range(W):
            if on[y0][x0] and not seen[y0][x0]:
                st = [(x0, y0)]; seen[y0][x0] = True; n = 0; bx = [x0, y0, x0, y0]
                while st:
                    x, y = st.pop(); n += 1
                    bx = [min(bx[0], x), min(bx[1], y), max(bx[2], x), max(bx[3], y)]
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        u, v = x + dx, y + dy
                        if 0 <= u < W and 0 <= v < H and on[v][u] and not seen[v][u]: seen[v][u] = True; st.append((u, v))
                if n > 1500: U = bx if U is None else [min(U[0], bx[0]), min(U[1], bx[1]), max(U[2], bx[2]), max(U[3], bx[3])]
    if U is None: return None
    b = U; return [clip.x0 + b[0] / z, clip.y0 + b[1] / z, clip.x0 + (b[2] + 1) / z, clip.y0 + (b[3] + 1) / z]
for f in sys.argv[1:]:
    pg = pymupdf.open(f)[2]
    row = []
    for clip in (pymupdf.Rect(100, 95, 505, 320), pymupdf.Rect(105, 385, 500, 612)):
        b = blob(pg, clip)
        row.append("none" if not b else "top %6.1f bot %6.1f left %6.1f right %6.1f centre (%6.1f,%6.1f) %5.1fx%5.1f" % (
            b[1], b[3], b[0], b[2], (b[0] + b[2]) / 2, (b[1] + b[3]) / 2, b[2] - b[0], b[3] - b[1]))
    print("%-28s c1 %s | c2 %s" % (f.split("/")[-1][:28], row[0], row[1]))
