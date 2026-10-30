# build.py REPO OUTDIR — lab sqz: Word for Windows' squeeze-or-stretch choice at a justified line's end,
# outside zh-3c055c9b's grid (lab gs2 covered that one: the automatic space at the line's end leaves with the piece;
# mark TYPE and LANGUAGE do not matter, mark COUNT does).
# Seven lines of the corpus where our decision and Word's differ (v2 census, 2026-10-30), each a whole one-paragraph document
# (the line + the piece + a short tail, in the paragraph's own pPr and its section), then one variable at a time:
#   F0 as is                      F7  the line's other marks -> 國 (mark count 0)
#   F1/F2/F3 compatibilityMode 12/14/15   F8  the piece -> 國s (an ideograph for a mark, a letter or a lone ×)
#   F4 docGrid removed            F9  right margin -2pt (more room)   F10 right margin +2pt
#   F5 docGrid type lines (pitch 312)  F6  characterSpacingControl doNotCompress
# Lines (Word's verdict on the piece, ours in brackets):
#   A zh-18cb2079 "…中国联通眉|山"        mode 12, lines grid   Word TAKES (we refuse)   need = 1 em, two marks give it
#   B zh-18cb2079 "…组织抢修供|电、"      mode 12, lines grid   Word TAKES (we refuse)
#   C zh-4e5fe46f "…应记录具体情|况。"    mode 14, lines grid   Word TAKES (we refuse)
#   D zh-e0ca7252 "…与廠商另行議|定。"    mode 15, no grid      Word TAKES (we refuse)
#   E zh-5be7e156 "…融合国际国内的|冷"    mode 14, linesAndChars Word TAKES (we refuse)
#   F zh-360c1df1 "…积极开|展"            mode 14, lines grid   Word REFUSES (we take)
#   G zh-6b242483 "…9（家）|×"            mode 14, lines grid   Word REFUSES (we take): a lone ×
import re, sys, os, zipfile
repo, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
CASES = [
 ("A", "zh-18cb2079", "中国电信眉山分公司、中国移动眉山分公司、中国联通眉", "山", 12),
 ("B", "zh-18cb2079", "工作职责：负责应急通信、电力等保障工作；组织抢修供", "电、", 12),
 ("C", "zh-4e5fe46f", "当事人或者有关人员拒绝接受调查和行政检查的，应记录具体情", "况。", 14),
 ("D", "zh-e0ca7252", "之給付標的或工作事項者，因此增加之服務費用由機關與廠商另行議", "定。", 15),
 ("E", "zh-5be7e156", "到2025年，衔接产地销地、贯通城市乡村、融合国际国内的", "冷", 14),
 ("F", "zh-360c1df1", "——实施“旅游促进各民族交往交流交融计划”。积极开", "展", 14),
 ("G", "zh-6b242483", "B.对B级企业开展执法检查，共计36个工作日。9（家）", "×", 14),
]
MARKS = set("、，。；：？！「」『』（）【】《》〈〉“”‘’…—")
def chars(p):
    res = []
    for r in re.findall(r"<w:r[ >].*?</w:r>", p, re.S):
        m = re.search(r"<w:rPr>.*?</w:rPr>", r, re.S); rpr = m.group(0) if m else ""
        for t in re.findall(r"<w:t(?: [^>]*)?>(.*?)</w:t>", r, re.S):
            t = t.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")
            res += [(c, rpr) for c in t]
    return res
def esc(t): return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
n = 0
for key, docid, line, piece, mode0 in CASES:
    src = next(os.path.join(repo, "test/corpus/docx/docs", f) for f in os.listdir(os.path.join(repo, "test/corpus/docx/docs")) if f.startswith(docid))
    z = zipfile.ZipFile(src); names = z.namelist(); data = {nm: z.read(nm) for nm in names}
    doc = data["word/document.xml"].decode("utf-8"); st = data["word/settings.xml"].decode("utf-8")
    body0 = doc.index("<w:body>") + 8
    found = None
    for m in re.finditer(r"<w:p[ >].*?</w:p>", doc[body0:], re.S):
        cs = chars(m.group(0)); ink = [(i, c) for i, (c, _) in enumerate(cs) if not c.isspace() and c != "　"]
        flat = "".join(c for _, c in ink); k = flat.find(line + piece)
        if k >= 0:
            found = (body0 + m.start(), body0 + m.end(), m.group(0), cs, ink[k][0], ink[k + len(line) + len(piece) - 1][0]); break
    assert found, (key, "not found")
    s0, e0, p, cs, a, b = found
    assert doc[:s0].count("<w:tc>") + doc[:s0].count("<w:tc ") == doc[:s0].count("</w:tc>"), (key, "in a table cell")
    first = all(c.isspace() for c, _ in cs[:a])
    seg = cs[a:min(len(cs), b + 7)]
    ppr = (re.search(r"<w:pPr>.*?</w:pPr>", p, re.S) or [""])[0] if "<w:pPr>" in p else ""
    ppr = re.sub(r"<w:rPr>.*?</w:rPr>", "", ppr, flags=re.S); ppr = re.sub(r"<w:sectPr.*?</w:sectPr>", "", ppr, flags=re.S)
    sm = None
    for m in re.finditer(r"<w:sectPr[ >].*?</w:sectPr>", doc[e0:], re.S): sm = m.group(0); break
    sect0 = sm
    if not first:
        # (A continuation line starts where Word's print has it: an explicit left indent from that x, no first-line or
        # hanging indent and no list number, which would have carried its own indent.)
        import pymupdf
        ref = os.path.join(repo, "test/corpus/docx/word-win", docid + "-orig.pdf") if False else next(os.path.join(repo, "test/corpus/docx/word-win", f) for f in os.listdir(os.path.join(repo, "test/corpus/docx/word-win")) if f.startswith(docid) and f.endswith("-orig.pdf"))
        x0 = None
        with pymupdf.open(ref) as d:
            for pg in d:
                r = pg.search_for(line[:10])
                if r:
                    x0 = r[0].x0
                    break
        assert x0 is not None, (key, "line not found in Word's print")
        ml = int(re.search(r'<w:pgMar[^>]*w:left="(-?\d+)"', sect0).group(1))
        ppr = re.sub(r"<w:numPr>.*?</w:numPr>", "", ppr, flags=re.S); ppr = re.sub(r"<w:ind [^>]*/>", "", ppr)
        ind = f'<w:ind w:left="{round((x0 - ml / 20) * 20)}" w:firstLine="0"/>'
        ppr = ppr.replace("</w:pPr>", ind + "</w:pPr>") if ppr else f"<w:pPr>{ind}</w:pPr>"
    # ink positions of the line / piece within seg, to edit by form
    inkseg = [i for i, (c, _) in enumerate(seg) if not c.isspace() and c != "　"]
    pstart = inkseg[len(line)]; pend = inkseg[len(line) + len(piece) - 1] + 1
    def build(form):
        s = list(seg); sect = sect0
        for i, (c, r) in enumerate(s):
            inpiece = pstart <= i < pend
            if form == "F7" and c in MARKS and not inpiece: s[i] = ("國", r)
            if form == "F8" and inpiece: s[i] = ("國", r)
        runs, cur, buf = [], None, ""
        for c, r in s:
            if r != cur and buf: runs.append((cur, buf)); buf = ""
            cur = r; buf += c
        if buf: runs.append((cur, buf))
        rx = "".join(f'<w:r>{r}<w:t xml:space="preserve">{esc(t)}</w:t></w:r>' for r, t in runs)
        stt = st
        mode = {"F1": 12, "F2": 14, "F3": 15}.get(form)
        if mode:
            if "compatibilityMode" in stt: stt = re.sub(r'(compatibilityMode"[^>]*w:val=")\d+', rf"\g<1>{mode}", stt)
            else:
                cm = f'<w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="{mode}"/>'
                stt = stt.replace("</w:compat>", cm + "</w:compat>") if "</w:compat>" in stt else stt.replace("</w:settings>", f"<w:compat>{cm}</w:compat></w:settings>")
        if form == "F6": stt = re.sub(r'(<w:characterSpacingControl w:val=")\w+', r"\g<1>doNotCompress", stt)
        if form == "F4": sect = re.sub(r"<w:docGrid[^>]*/>", "", sect)
        if form == "F5":
            sect = re.sub(r"<w:docGrid[^>]*/>", "", sect).replace("</w:sectPr>", '<w:docGrid w:type="lines" w:linePitch="312"/></w:sectPr>')
        if form in ("F9", "F10"):
            d = -40 if form == "F9" else 40
            sect = re.sub(r'(<w:pgMar[^>]*w:right=")(-?\d+)', lambda m: m.group(1) + str(int(m.group(2)) + d), sect)
        newdoc = doc[:body0] + f"<w:p>{ppr}{rx}</w:p>{sect}</w:body></w:document>"
        return newdoc, stt
    for form in ["F0", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10"]:
        if form in ("F1", "F2", "F3") and {"F1": 12, "F2": 14, "F3": 15}[form] == mode0: continue
        if form == "F4" and 'w:type=' not in (re.search(r"<w:docGrid[^>]*/>", sect0) or [""])[0]: continue
        if form == "F5" and 'w:type="lines"' in (re.search(r"<w:docGrid[^>]*/>", sect0) or [""])[0]: continue
        if form == "F6" and "doNotCompress" in st: continue
        nd, ns = build(form)
        with zipfile.ZipFile(os.path.join(out, f"t-{key}-{form}.docx"), "w", zipfile.ZIP_DEFLATED) as w:
            for nm in names:
                w.writestr(nm, nd.encode("utf-8") if nm == "word/document.xml" else ns.encode("utf-8") if nm == "word/settings.xml" else data[nm])
        n += 1
print(n, "documents in", out)
