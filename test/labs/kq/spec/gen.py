#!/usr/bin/env python3
"""Lab kq (Windows 01QbbApP, for amd-opus): kinsoku off/on, closing mark at a justified line end, compat 12 and 15, 16pt 標楷體.
gen.py cal OUT | gen.py test OUT widths.json
Line = L (26 ideographs, k inner commas) + MARK + FILL.  jc both, compressPunctuation, exact 36pt, no grid, zh-TW.
marks: c = '，'  d = '、'  q = '”' (own run, hint eastAsia)  r = '难”' (the ideograph 难 then the quote, i.e. quote after an ideograph inside continuing text)
w:kinsoku val 1 / 0.  test: one paragraph per W, W = natural(base) + i*0.5, i=0..32, base = L (L+难 for r), so the mark runs 16 .. 0 pt over."""
import sys, os, json, zipfile
POOL = "各等級全體訓練單位之招募兼具豐富政府機關辦理考核成績優良人員獎勵措施規定事項"
L0 = [POOL[i % len(POOL)] for i in range(25)] + ["移"]        # 26 ideographs
FILL = "後續文字繼續排版使用國家政府機關辦理考核成績優良人員獎勵措施之規定事項"
W_ = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
POS = {0: [], 1: [8], 2: [8, 17], 4: [5, 10, 15, 20]}
MARKS = {"c": "，", "d": "、", "q": "”", "r": "难”"}
BASE = '<w:sz w:val="32"/><w:szCs w:val="32"/><w:lang w:eastAsia="zh-TW"/>'
F = '<w:rFonts w:ascii="標楷體" w:hAnsi="標楷體" w:eastAsia="標楷體"/>'
FH = '<w:rFonts w:ascii="標楷體" w:hAnsi="標楷體" w:eastAsia="標楷體" w:hint="eastAsia"/>'


def ltext(k):
    out = []
    for i, c in enumerate(L0):
        out.append(c)
        if i + 1 in POS[k]:
            out.append("，")
    return "".join(out)


def run(t, hint=False):
    return '<w:r><w:rPr>' + (FH if hint else F) + BASE + '</w:rPr><w:t xml:space="preserve">' + t + '</w:t></w:r>'


def line(k, mark, with_tail=True):
    l = ltext(k)
    if mark == "r":
        return run(l + "难") + run("”", True) + (run(FILL) if with_tail else "")
    if mark == "q":
        return run(l) + run("”", True) + (run(FILL) if with_tail else "")
    return run(l + MARKS[mark] + (FILL if with_tail else ""))


def base_line(k, mark):
    return run(ltext(k) + ("难" if mark == "r" else ""))


def para(runs, kin, rind=0, jc="left"):
    return ('<w:p><w:pPr><w:kinsoku w:val="%d"/><w:spacing w:before="0" w:after="0" w:line="720" w:lineRule="exact"/><w:ind w:left="0" w:right="%d"/><w:jc w:val="%s"/></w:pPr>%s</w:p>' % (kin, rind, jc, runs))


def pkg(path, body, compat):
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="720" w:bottom="1440" w:left="720" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W_, body, sect)
    sty = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles %s><w:docDefaults><w:rPrDefault><w:rPr>%s%s</w:rPr></w:rPrDefault></w:docDefaults>'
           '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>' % (W_, F, BASE))
    st = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings %s><w:characterSpacingControl w:val="compressPunctuation"/><w:compat>'
          '<w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="%d"/></w:compat></w:settings>' % (W_, compat))
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
    root = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    dr = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, v in (("[Content_Types].xml", ct), ("_rels/.rels", root), ("word/document.xml", doc), ("word/styles.xml", sty), ("word/settings.xml", st), ("word/_rels/document.xml.rels", dr)):
            z.writestr(n, v)


if __name__ == "__main__":
    mode, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    if mode == "cal":
        for compat in (12, 15):
            body = ""
            ks = []
            for mark in "cr":
                for k in (0, 1, 2, 4):
                    body += para(base_line(k, "r" if mark == "r" else "c"), 1)
                    ks.append("%s-%d" % ("r" if mark == "r" else "L", k))
            n = "cal-m%d" % compat
            pkg(os.path.join(out, n + ".docx"), body, compat)
            json.dump(ks, open(os.path.join(out, n + ".keys"), "w"))
            print(n)
    else:
        Wd = json.load(open(sys.argv[3]))   # {"m12": {"L-0": nat, "r-0": nat}}
        for compat in (12, 15):
            for kin in (1, 0):
                for mark in "cdqr":
                    body = ""
                    meta = []
                    for k in (0, 1, 2, 4):
                        nat = Wd["m%d" % compat][("r-%d" if mark == "r" else "L-%d") % k]
                        for i in range(33):
                            w = nat + i * 0.5
                            body += para(line(k, mark), kin, 10466 - round(w * 20), "both")
                            meta.append((k, w))
                    n = "kq-m%d-k%d-%s" % (compat, kin, mark)
                    pkg(os.path.join(out, n + ".docx"), body, compat)
                    json.dump(meta, open(os.path.join(out, n + ".meta"), "w"))
                    print(n, len(meta))
