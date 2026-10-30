# census.py REPO WORKDIR [WORKDIR...] — every Word line v2 leaves unmatched, grouped into incidents
# (consecutive misses on a page in reading order) and classed by the incident's first line. JSON to stdout.
import sys, os, json, importlib.util, unicodedata, bisect
os.environ["DOCX_LINE_MATCH"] = "v2"; os.environ["DOCX_LINE_READER"] = "mupdf"
repo = sys.argv[1]
spec = importlib.util.spec_from_file_location("lm", os.path.join(repo, "test/docx-line-match.py"))
lm = importlib.util.module_from_spec(spec); spec.loader.exec_module(lm)
import pymupdf
REFS = os.path.join(repo, "test/corpus/docx/word-win")
SKIP = ("zh-6a4fc013", "rtl")
def page_geom(pdf):
    out = []
    with pymupdf.open(pdf) as d:
        for pg in d:
            H, W = pg.rect.height, pg.rect.width
            vert, horiz, fills, imgs = [], [], [], [r["bbox"] for r in pg.get_image_info()]
            for dr in pg.get_drawings():
                for it in dr["items"]:
                    if it[0] == "l":
                        a, b = it[1], it[2]
                        if abs(a.x - b.x) < 0.5 and abs(a.y - b.y) > 4: vert.append((a.x, min(a.y, b.y), max(a.y, b.y)))
                        elif abs(a.y - b.y) < 0.5 and abs(a.x - b.x) > 4: horiz.append((a.y, min(a.x, b.x), max(a.x, b.x)))
                    elif it[0] == "re":
                        r = it[1]
                        if dr.get("fill") is not None and r.width < W * 0.9: fills.append((r.x0, r.y0, r.x1, r.y1))
                        if r.width < 1.5 and r.height > 4: vert.append((r.x0, r.y0, r.y1))
                        if r.height < 1.5 and r.width > 4: horiz.append((r.y0, r.x0, r.x1))
                        if dr.get("color") is not None and r.width > 4 and r.height > 4:
                            vert += [(r.x0, r.y0, r.y1), (r.x1, r.y0, r.y1)]; horiz += [(r.y0, r.x0, r.x1), (r.y1, r.x0, r.x1)]
            out.append(dict(H=H, W=W, vert=vert, horiz=horiz, fills=fills, imgs=imgs))
    return out
def region(g, r):
    y = -r[1]; x0 = r[2]; x1 = r[5] if len(r) > 5 else x0 + 10
    inimg = any(a <= x0 + 1 and x1 - 1 <= c and b - 2 <= y <= d + 8 for a, b, c, d in g["imgs"])
    left = any(abs(x - x0) < 40 and x <= x0 + 1 and y0 - 2 <= y <= y1 + 6 for x, y0, y1 in g["vert"])
    right = any(x >= x1 - 1 and x - x1 < 60 and y0 - 2 <= y <= y1 + 6 for x, y0, y1 in g["vert"])
    nfills = sum(1 for a, b, c, d in g["fills"] if b - 30 <= y <= d + 30)
    if y < 72 or y > g["H"] - 60: return "header/footer"
    if inimg or nfills >= 8: return "chart/drawing"
    if left and right: return "table/box"
    return "body"
def run(work):
    res = []
    for f in sorted(os.listdir(os.path.join(work, "pdf"))):
        if not f.endswith(".pdf") or f.startswith(SKIP): continue
        ref = os.path.join(REFS, f[:-4] + "-orig.pdf")
        if not os.path.exists(ref): continue
        ours_pdf = os.path.join(work, "pdf", f)
        a, b = lm.lines(None, ref), lm.lines(None, ours_pdf)
        bp, wp = {}, {}
        for r in b: bp.setdefault(r[0], []).append(r)
        for r in a: wp.setdefault(r[0], []).append(r)
        missed = set()
        for p in wp:
            for r in lm.unmatched(wp[p], bp.get(p, [])): missed.add(id(r))
        if not missed: continue
        geo = page_geom(ref)
        allours = {}
        for r in b: allours.setdefault(r[3][:4], []).append(r)
        inc = []
        for i, r in enumerate(a):
            if id(r) not in missed: continue
            if inc and inc[-1]["end"] == i - 1 and inc[-1]["page"] == r[0]:
                inc[-1]["end"] = i; inc[-1]["n"] += 1; continue
            # where ours set this text
            same = [o for o in b if lm.same_start(o[3], r[3])]
            onpage = [o for o in same if o[0] == r[0]]
            near = min(onpage, key=lambda o: abs(o[1] - r[1])) if onpage else None
            other = min(same, key=lambda o: (abs(o[0] - r[0]), abs(o[1] - r[1]))) if same and not onpage else None
            g = geo[r[0] - 1] if r[0] - 1 < len(geo) else geo[-1]
            inc.append(dict(page=r[0], start=i, end=i, n=1, y=-r[1], x=r[2], text=r[3][:24], reg=region(g, r),
                            dy=(near[1] - r[1]) if near else None, dx=(near[2] - r[2]) if near else None,
                            otherpage=(other[0] - r[0]) if other else None, short=len(r[3]) < 4))
        res.append(dict(doc=f[:-4][:14], wlines=len(a), olines=len(b), missed=len(missed),
                        pages=(max(r[0] for r in a), max(r[0] for r in b)), inc=inc))
    return res
out = []
for w in sys.argv[2:]: out += run(w)
json.dump(out, sys.stdout, ensure_ascii=False)
