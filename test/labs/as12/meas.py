# meas.py PDF... — lab as12: per print, every line of the page as "x_end  text", and for each line holding "第" followed by a
# digit run the pitch of every character from the one before "第" through the ideograph after the digits (x of the next glyph
# minus x of this one), which shows the bracket widths and the two automatic spaces: after 第 (14.0 + gap) and after the digits.
import sys, pymupdf
for f in sorted(sys.argv[1:]):
    pg = pymupdf.open(f)[0]
    print("==", f.split("/")[-1])
    rows = []
    for b in pg.get_text("rawdict")["blocks"]:
        for l in b.get("lines", []):
            ch = [c for s in l["spans"] for c in s["chars"]]
            if ch: rows.append((round(l["bbox"][1], 1), ch))
    for y, ch in sorted(rows, key=lambda r: r[0]):
        t = "".join(c["c"] for c in ch)
        if not t.strip(): continue
        print("  y %6.1f  end %6.1f  %s" % (y, ch[-1]["bbox"][2], t[:40]))
        i = t.find("第8")
        if i >= 0:
            a = max(0, i - 4)
            seg = [c for c in ch[a:] ]
            j = next((k for k in range(i + 1, len(t)) if not (t[k].isdigit() or t[k] == " ")), None)
            seg = ch[a:(j + 1 if j else len(ch))]
            print("      pitch:", " ".join("%s%.1f" % (c["c"] if c["c"] != " " else "_", seg[k + 1]["bbox"][0] - c["bbox"][0]) for k, c in enumerate(seg[:-1])))
