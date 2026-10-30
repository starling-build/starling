# classify.py census.json — first cause per incident, rolled up by class, documents and lines.
import json, sys, collections
R = json.load(open(sys.argv[1]))
def cls(i):
    if i["reg"] == "header/footer": return "header/footer"
    if i["reg"] == "chart/drawing": return "chart/drawing"
    if i["otherpage"] is not None: return "pagination"
    if i["dy"] is not None:
        if abs(i["dy"]) <= 3: return "x-only/reader" if not i["short"] else "short-piece x"
        return ("table/box shift" if i["reg"] == "table/box" else "body shift (height/spacing above)")
    return "table/box break" if i["reg"] == "table/box" else "line break / width"
by = collections.defaultdict(lambda: [0, 0, collections.Counter()])
for d in R:
    for i in d["inc"]:
        c = cls(i); i["cls"] = c
        by[c][0] += i["n"]; by[c][1] += 1; by[c][2][d["doc"]] += i["n"]
tot = sum(v[0] for v in by.values())
print("total missed lines", tot, "in", len(R), "documents")
for c, (n, k, docs) in sorted(by.items(), key=lambda t: -t[1][0]):
    print("%-34s %5d lines %4d incidents %3d docs | top: %s" % (c, n, k, len(docs), ", ".join("%s %d" % (d, m) for d, m in docs.most_common(6))))
json.dump(R, open(sys.argv[1].replace(".json", "-cls.json"), "w"), ensure_ascii=False)
