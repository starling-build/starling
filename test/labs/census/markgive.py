# markgive.py REFDIR [MAXDOCS] — for each (font, mark): the smallest step (advance to the next glyph, / font size) a mark takes
# mid-line in Word's prints, with the count of lines and how many sit below 0.99 (squeezed).
import sys, os, collections, pymupdf
ref = sys.argv[1]; maxdocs = int(sys.argv[2]) if len(sys.argv) > 2 else 120
MARKS = "，。、；：！？）」』】》〉（「『【《〈“”‘’"
stats = collections.defaultdict(list)
files = sorted(f for f in os.listdir(ref) if f.startswith("zh-") and f.endswith("-orig.pdf"))[:maxdocs]
for fn in files:
    try: doc = pymupdf.open(os.path.join(ref, fn))
    except Exception: continue
    for pg in doc:
        for b in pg.get_text("rawdict")["blocks"]:
            for l in b.get("lines", []):
                if tuple(round(v, 2) for v in l["dir"]) != (1.0, 0.0): continue
                cs = [(c, s["font"], s["size"]) for s in l["spans"] for c in s["chars"] if c["c"] not in " 　"]
                for (c, font, size), (n, _, _) in zip(cs, cs[1:]):
                    if c["c"] in MARKS and n["c"] not in MARKS and size >= 9:
                        stats[(font[:24], c["c"], round(size))].append((n["origin"][0] - c["origin"][0]) / size)
out = []
for (font, ch, size), v in stats.items():
    if len(v) >= 8: out.append((font, ch, size, len(v), min(v), sum(1 for x in v if x < 0.99)))
out.sort(key=lambda r: (r[0], r[1], r[2]))
for r in out: print("%-24s %s %2dpt n=%4d min step %.3f em  squeezed %d" % r)
