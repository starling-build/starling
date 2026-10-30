# meas.py PDF... — for each print, how the three witness spots break: the line that ends before or with the mark.
import sys, pymupdf
KEYS = [("p44", "不適用行政程序法之程序規定", "，應作狹義解釋"), ("p55", "選擇其一項或數項", "，同時或先後為之"), ("p49", "影響機關業務運作）", "。")]
for f in sorted(sys.argv[1:]):
    doc = pymupdf.open(f); lines = []
    for pg in doc:
        for b in pg.get_text("dict")["blocks"]:
            for l in b.get("lines", []):
                t = "".join(s["text"] for s in l["spans"]).replace(" ", "")
                if t: lines.append(t)
    out = []
    for tag, end, nxt in KEYS:
        i = next((i for i, t in enumerate(lines) if end in t), None)
        if i is None: out.append(tag + " ?"); continue
        t = lines[i]; n = lines[i + 1] if i + 1 < len(lines) else ""
        out.append("%s %s | %s" % (tag, "…" + t[-6:], n[:6]))
    print("%-10s %s" % (f.split("/")[-1][:10], "   ".join(out)))
