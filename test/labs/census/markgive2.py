# markgive2.py REFDIR OUT.tsv — Word for Windows' step after every mark, all prints, by (face, size, mark, context):
# context = ideograph | mark | latin | linefinal; columns: n, min step (em), p10, median, count below 0.97 (squeezed).
import sys, os, collections, statistics, pymupdf
ref, out = sys.argv[1], sys.argv[2]
MARKS = "，。、；：！？）」』】》〉（「『【《〈“”‘’"
def ctx(n):
    if n is None: return "linefinal"
    ch = n["c"]
    if ch in MARKS: return "mark"
    if '㐀' <= ch <= '鿿' or '豈' <= ch <= '﫿': return "ideograph"
    return "latin"
stats = collections.defaultdict(list)
for fn in sorted(os.listdir(ref)):
    if not fn.endswith("-orig.pdf"): continue
    try: doc = pymupdf.open(os.path.join(ref, fn))
    except Exception: continue
    for pg in doc:
        for b in pg.get_text("rawdict")["blocks"]:
            for l in b.get("lines", []):
                if tuple(round(v, 2) for v in l["dir"]) != (1.0, 0.0): continue
                cs = [(c, s["font"], s["size"]) for s in l["spans"] for c in s["chars"] if c["c"] not in " 　"]
                for i, (c, font, size) in enumerate(cs):
                    if c["c"] not in MARKS or size < 8: continue
                    if i + 1 < len(cs):
                        n = cs[i + 1][0]; step = (n["origin"][0] - c["origin"][0]) / size
                    else:
                        n = None; step = (c["bbox"][2] - c["origin"][0]) / size
                    stats[(font[:26], round(size), c["c"], ctx(n))].append(step)
rows = []
for (font, size, ch, cx), v in stats.items():
    if len(v) < 5: continue
    v.sort(); rows.append((font, size, ch, cx, len(v), v[0], v[len(v) // 10], statistics.median(v), sum(1 for x in v if x < 0.97)))
rows.sort(key=lambda r: (r[0], r[1], r[2], r[3]))
with open(out, "w") as f:
    f.write("font\tsize\tmark\tcontext\tn\tmin\tp10\tmedian\tsqueezed\n")
    for r in rows: f.write("%s\t%d\t%s\t%s\t%d\t%.3f\t%.3f\t%.3f\t%d\n" % r)
print(len(rows), "rows from", sum(len(v) for v in stats.values()), "marks")
