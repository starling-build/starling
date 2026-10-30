# build.py SRC.docx OUTDIR — lab gs2: Word for Windows' squeeze-or-stretch choice at a
# justified line's end (zh-3c055c9b: mode 15, 17pt character grid, PMingLiU 16pt, zh-TW,
# overflowPunct 0). Each document is ONE paragraph: the text of one line of Word's print
# plus the piece Word took or sent down and a short tail, in the paragraph's own pPr (a
# continuation line's first-line/hanging indent zeroed so it starts where it did).
# Three lines x six forms x three right indents (the paragraph's own, -2pt, +2pt):
#   L1 "…不實填寫「109年5月24日、餐" + "費、"  (Word: sent down; 4 marks, 5 automatic spaces)
#   L2 "…【附件12，第257" + "頁】，"           (Word: taken; 4 marks, 3 spaces)
#   L3 "(一)" (its list number) + "古佳川…「長治鄉德協大字鍾" + "○" (Word: sent down; 1 mark, 2 spaces; a first line)
# forms: F0 as is; F1 no automatic spaces (ASCII digits and letters made full-width);
#   F2 the line's marks outside the piece made ideographs (國); F3 one mark only (the
#   piece's last; every other mark 國); F4 every mark "，"; F5 the runs' East Asian
#   language zh-CN.
import re, sys, os, zipfile
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src); names = z.namelist(); data = {n: z.read(n) for n in names}
doc = data["word/document.xml"].decode("utf-8")
body0 = doc.index("<w:body>") + len("<w:body>"); sect = doc.rindex("<w:sectPr")
paras = re.findall(r"<w:p[ >].*?</w:p>", doc[body0:sect], re.S)
def chars(p):
    out = []
    for r in re.findall(r"<w:r[ >].*?</w:r>", p, re.S):
        rpr = (re.search(r"<w:rPr>.*?</w:rPr>", r, re.S) or [""])[0] if re.search(r"<w:rPr>.*?</w:rPr>", r, re.S) else ""
        for t in re.findall(r"<w:t(?: [^>]*)?>(.*?)</w:t>", r, re.S):
            t = t.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")
            out += [(c, rpr) for c in t]
    return out
CASES = [("L1", "廳負責人同意，不實填寫「109年5月24日、餐", "費、", False),
         ("L2", "當天生日宴會是私人行程等語【附件12，第257", "頁】，", False),
         ("L3", "古佳川前因涉嫌在LINE群組「長治鄉德協大字鍾", "○", True)]
MARKS = set("、，。：；？！「」『』（）【】《》〈〉…—")
def full(c):
    o = ord(c)
    return chr(o - 0x20 + 0xFF00) if (0x30 <= o <= 0x39 or 0x41 <= o <= 0x5A or 0x61 <= o <= 0x7A) else c
n = 0
for key, line, piece, first in CASES:
    p = next(p for p in paras if line[4:12] in "".join(c for c, _ in chars(p)))
    cs = chars(p); text = "".join(c for c, _ in cs)
    a = text.index(line[:10]); b = text.index(piece, a + len(line) - 2) + len(piece)
    seg = cs[a:min(len(cs), b + 6)]
    assert "".join(c for c, _ in seg).startswith(line + piece), (key, "".join(c for c, _ in seg))
    ppr = (re.search(r"<w:pPr>.*?</w:pPr>", p, re.S) or [""])[0]
    ppr = re.sub(r"<w:rPr>.*?</w:rPr>", "", ppr, flags=re.S)
    if not first:
        ppr = re.sub(r' w:(firstLine|hanging|firstLineChars|hangingChars)="[^"]*"', "", ppr)
    m = re.search(r'<w:ind [^>]*w:right="(-?\d+)"', ppr); right = int(m.group(1)) if m else 0
    pend = len(line) + len(piece)
    for form in range(6):
        s = []
        for i, (c, rpr) in enumerate(seg):
            inpiece = len(line) <= i < pend
            if form == 1: c = full(c)
            if form == 2 and c in MARKS and not inpiece: c = "國"
            if form == 3 and c in MARKS and i != pend - 1: c = "國"
            if form == 4 and c in MARKS: c = "，"
            if form == 5:
                rpr = rpr or "<w:rPr></w:rPr>"
                rpr = re.sub(r"<w:lang [^>]*/>", "", rpr).replace("</w:rPr>", '<w:lang w:eastAsia="zh-CN"/></w:rPr>')
            s.append((c, rpr))
        runs, cur, buf = [], None, ""
        for c, rpr in s:
            if rpr != cur and buf: runs.append((cur, buf)); buf = ""
            cur = rpr; buf += c
        if buf: runs.append((cur, buf))
        rx = "".join(f"<w:r>{r}<w:t xml:space=\"preserve\">{t.replace('&','&amp;').replace('<','&lt;')}</w:t></w:r>" for r, t in runs)
        for dr in (0, -40, 40):
            pp = ppr
            if "<w:ind " in pp:
                pp = re.sub(r'(<w:ind [^>]*?)( w:right="-?\d+")?(\s*/>)', lambda m: m.group(1) + f' w:right="{right + dr}"' + m.group(3), pp, count=1)
            else:
                pp = pp.replace("</w:pPr>", f'<w:ind w:right="{right + dr}"/></w:pPr>') if pp else f'<w:pPr><w:ind w:right="{right + dr}"/></w:pPr>'
            newdoc = doc[:body0] + f"<w:p>{pp}{rx}</w:p>" + doc[sect:]
            name = f"t-{key}-F{form}-r{'+' if dr > 0 else '-' if dr < 0 else '0'}{abs(dr) // 20 if dr else ''}.docx"
            with zipfile.ZipFile(os.path.join(out, name), "w", zipfile.ZIP_DEFLATED) as w:
                for nm in names: w.writestr(nm, newdoc.encode("utf-8") if nm == "word/document.xml" else data[nm])
            n += 1
print(n, "documents in", out)
