# charunit.py REPO [MAXDOCS] — Word for Windows' unit for a *Chars indent, per (PDF face, size): for each body paragraph with
# w:firstLineChars (no left indent, no hanging), indent = x(first line) - x(next line) in Word's print, unit = indent / (chars/100).
import sys, os, re, zipfile, collections, unicodedata, statistics, json, pymupdf
repo = sys.argv[1]; OURS = sys.argv[2]; maxdocs = int(sys.argv[3]) if len(sys.argv) > 3 else 700
D = os.path.join(repo, "test/corpus/docx/docs"); R = os.path.join(repo, "test/corpus/docx/word-win")
norm = lambda t: "".join(c for c in unicodedata.normalize("NFKC", t) if not c.isspace())
rows = []
for fn in sorted(os.listdir(D))[:maxdocs]:
    if not fn.endswith(".docx"): continue
    key = fn[:-5]; ref = os.path.join(R, key + "-orig.pdf")
    if not os.path.exists(ref): continue
    try:
        z = zipfile.ZipFile(os.path.join(D, fn)); doc = z.read("word/document.xml").decode("utf-8")
    except Exception: continue
    paras = []
    for p in re.findall(r"<w:p[ >].*?</w:p>", doc, re.S):
        m = re.search(r'<w:ind [^>]*w:firstLineChars="(\d+)"[^>]*>', p)
        sf = re.search(r'w:firstLine="(\d+)"', m.group(0)) if m else None
        if not m: continue
        ind = m.group(0)
        if re.search(r'w:(left|start|leftChars|hanging|hangingChars)="[1-9]', ind): continue
        if "<w:numPr>" in p or "<w:tbl" in p: continue
        t = norm("".join(re.findall(r"<w:t[^>]*>([^<]*)</w:t>", p)))
        if len(t) >= 20 and int(m.group(1)) > 0: paras.append((int(m.group(1)), t, int(sf.group(1)) if sf else None))
    if not paras: continue
    try: pdf = pymupdf.open(ref); opdf = pymupdf.open(os.path.join(OURS, "pdf", fn[:-5] + ".pdf"))
    except Exception: continue
    lines = []
    for pn, pg in enumerate(pdf):
        for b in pg.get_text("rawdict")["blocks"]:
            bl = [l for l in b.get("lines", []) if tuple(round(v, 2) for v in l["dir"]) == (1.0, 0.0)]
            for k, l in enumerate(bl):
                cs = [(c, s["font"], s["size"]) for s in l["spans"] for c in s["chars"] if c["c"].strip()]
                if cs: lines.append((pn, k, bl, cs))
    def lines_of(doc):
        out = []
        for pn, pg in enumerate(doc):
            for b in pg.get_text("rawdict")["blocks"]:
                bl = [l for l in b.get("lines", []) if tuple(round(v, 2) for v in l["dir"]) == (1.0, 0.0)]
                for k, l in enumerate(bl):
                    cs = [(c, s["font"], s["size"]) for s in l["spans"] for c in s["chars"] if c["c"].strip()]
                    if cs: out.append((pn, k, bl, cs))
        return out
    index = collections.defaultdict(list)
    for pn, k, bl, cs in lines:
        index["".join(c["c"] for c, _, _ in cs[:8])].append((pn, k, bl, cs))
    oindex = collections.defaultdict(list)
    for pn, k, bl, cs in lines_of(opdf):
        oindex["".join(c["c"] for c, _, _ in cs[:8])].append((pn, k, bl, cs))
    for chars, t, stored in paras:
        hit = index.get(t[:8])
        if not hit or len(hit) != 1: continue
        pn, k, bl, cs = hit[0]
        if k + 1 >= len(bl): continue
        nxt = [c for s in bl[k + 1]["spans"] for c in s["chars"] if c["c"].strip()]
        if not nxt: continue
        lt = "".join(c["c"] for c, _, _ in cs); nt = "".join(c["c"] for c in nxt)
        if t.find(norm(lt) + norm(nt)[:4]) != 0: continue
        indent = cs[0][0]["origin"][0] - nxt[0]["origin"][0]
        if not (3 < indent < 120): continue
        oh = oindex.get(t[:8]); oi = None
        if oh and len(oh) == 1:
            _, ok, obl, ocs = oh[0]
            if ok + 1 < len(obl):
                onxt = [c for s in obl[ok + 1]["spans"] for c in s["chars"] if c["c"].strip()]
                if onxt: oi = ocs[0][0]["origin"][0] - onxt[0]["origin"][0]
        rows.append((key[:12], chars, cs[0][1][:26], round(cs[0][2], 1), round(indent / (chars / 100), 3), stored, round(indent, 2), None if oi is None else round(oi, 2)))
by = collections.defaultdict(list)
for key, chars, font, size, unit, stored, ind, oi in rows: by[(font, size)].append(unit)
print(len(rows), "paragraphs")
out = []
for (font, size), v in by.items():
    if len(v) >= 3:
        c = collections.Counter(round(x, 2) for x in v).most_common(2)
        out.append((font, size, len(v), statistics.median(v), c, statistics.median(v) / size))
for r in sorted(out, key=lambda r: -r[2])[:40]:
    print("%-26s %5.1fpt n=%4d median unit %.3f (%.4f of size)  top %s" % (r[0], r[1], r[2], r[3], r[5], r[4]))
json.dump(rows, open(os.path.expanduser("~/starling-word-check/lab/census/charunit.json"), "w"), ensure_ascii=False)

agree = collections.Counter()
for key, chars, font, size, unit, stored, ind, oi in rows:
    if stored is None or oi is None: continue
    ours_ok = abs(oi - ind) < 0.08
    stored_ok = abs(stored / 20 - ind) < 0.08
    k = ("ours right" if ours_ok else "ours wrong") + (", stored right" if stored_ok else ", stored wrong")
    agree[k] += 1
    if not ours_ok: print(k, key, font, size, "chars", chars, "word %.2f ours %.2f stored %.2f" % (ind, oi, stored / 20))
print(dict(agree))
