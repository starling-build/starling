#!/usr/bin/env python3
"""Lab csq (Windows 01QbbApP, for amd-opus/starling-47): how far a CELL line squeezes to take the next ideograph X.
12pt 標楷體 zh-TW (Latin in the same face), jc both, compressPunctuation, useFELayout + balanceSingleByteDoubleByteWidth, fixed exact 24pt lines.
Line = L + [digit] + X + FILL.  L = n ideographs (13|26) with k marks (1|2|3), d single digits (0|1|3), p = a digit right before X (0|1).
marks: c = all ，  d = all 、  s = ，and ；alternating.  Mark/digit positions are after ideograph index (1-based):
  n13 marks {1:[6], 2:[4,9], 3:[3,6,10]}, digits {1:[2], 3:[2,5,8]};  n26 marks {1:[13], 2:[8,17], 3:[6,13,20]}, digits {1:[2], 3:[2,5,10]}.
gen.py cal OUT          : per compat 14/15, one doc with the 108 left-aligned L+X lines (natural width)
gen.py test OUT widths.json : cell docs (compat 15, k 1..3), body docs (compat 15, k 2, right indent = 10466 - W), cell docs compat 14 (k 2);
                          W = natural(L+X) - 12 + 0.25 i, i = 0..48"""
import sys, os, json, zipfile, itertools
POOL = "各等級全體訓練單位之招募兼具豐富政府機關辦理考核成績優良人員獎勵措施規定事項"
FILL = "後續文字繼續排版使用國家政府機關辦理考核成績優良人員獎勵措施之規定事項"
X = "移"
W_ = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
MPOS = {13: {1: [6], 2: [4, 9], 3: [3, 6, 10]}, 26: {1: [13], 2: [8, 17], 3: [6, 13, 20]}}
DPOS = {13: {0: [], 1: [2], 3: [2, 5, 8]}, 26: {0: [], 1: [2], 3: [2, 5, 10]}}
BASE = '<w:sz w:val="24"/><w:szCs w:val="24"/><w:lang w:eastAsia="zh-TW"/>'
F = '<w:rFonts w:ascii="標楷體" w:hAnsi="標楷體" w:eastAsia="標楷體"/>'


def mark_chars(kind, k):
    if kind == "c":
        return ["，"] * k
    if kind == "d":
        return ["、"] * k
    return ["，", "；", "，"][:k]


def ltext(n, mkind, k, d, p, with_x=True, tail=False):
    mp = dict(zip(MPOS[n][k], mark_chars(mkind, k)))
    dp = dict(zip(DPOS[n][d], "357"))
    out = []
    for i in range(1, n + 1):
        out.append(POOL[i - 1])
        if i in dp:
            out.append(dp[i])
        if i in mp:
            out.append(mp[i])
    if p:
        out.append("4")
    if with_x:
        out.append(X)
    if tail:
        out.append(FILL)
    return "".join(out)


def run(t):
    return '<w:r><w:rPr>' + F + BASE + '</w:rPr><w:t xml:space="preserve">' + t + '</w:t></w:r>'


def para(t, rind=0, jc="left"):
    return ('<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="480" w:lineRule="exact"/><w:ind w:left="0" w:right="%d"/><w:jc w:val="%s"/></w:pPr>%s</w:p>' % (rind, jc, run(t)))


def cell(inner, wtw):
    return ('<w:tbl><w:tblPr><w:tblW w:w="%d" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar></w:tblPr>'
            '<w:tblGrid><w:gridCol w:w="%d"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/></w:tcPr>%s</w:tc></w:tr></w:tbl>'
            '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="40" w:lineRule="exact"/></w:pPr></w:p>' % (wtw, wtw, wtw, inner))


def pkg(path, body, compat):
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="720" w:bottom="1440" w:left="720" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W_, body, sect)
    sty = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles %s><w:docDefaults><w:rPrDefault><w:rPr>%s%s</w:rPr></w:rPrDefault></w:docDefaults>'
           '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>' % (W_, F, BASE))
    st = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings %s><w:characterSpacingControl w:val="compressPunctuation"/><w:compat>'
          '<w:balanceSingleByteDoubleByteWidth/><w:useFELayout/>'
          '<w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="%d"/></w:compat></w:settings>' % (W_, compat))
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
    root = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    dr = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, v in (("[Content_Types].xml", ct), ("_rels/.rels", root), ("word/document.xml", doc), ("word/styles.xml", sty), ("word/settings.xml", st), ("word/_rels/document.xml.rels", dr)):
            z.writestr(n, v)


def key(n, m, d, p, k):
    return "L%d-m%s-d%d-p%d-k%d" % (n, m, d, p, k)


CONDS = list(itertools.product((13, 26), "cds", (0, 1, 3), (0, 1)))
if __name__ == "__main__":
    mode, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    if mode == "cal":
        for compat in (14, 15):
            body, keys = "", []
            for (n, m, d, p) in CONDS:
                for k in (1, 2, 3):
                    body += para(ltext(n, m, k, d, p))
                    keys.append(key(n, m, d, p, k))
            nm = "cal-c%d" % compat
            pkg(os.path.join(out, nm + ".docx"), body, compat)
            json.dump(keys, open(os.path.join(out, nm + ".keys"), "w"))
            print(nm)
    else:
        Wd = json.load(open(sys.argv[3]))
        plan = [("c15", "cell", 15, (1, 2, 3)), ("c15", "body", 15, (2,)), ("c14", "cell", 14, (2,))]
        for tag, cont, compat, ks in plan:
            for (n, m, d, p) in CONDS:
                body, meta = "", []
                for k in ks:
                    nat = Wd["c%d" % compat][key(n, m, d, p, k)]
                    for i in range(49):
                        w = nat - 12 + 0.25 * i
                        t = ltext(n, m, k, d, p, tail=True)
                        body += para(t, 10466 - round(w * 20), "both") if cont == "body" else cell(para(t, 0, "both"), round(w * 20))
                        meta.append((k, w, nat))
                nm = "csq-%s-%s-L%d-m%s-d%d-p%d" % (tag, cont, n, m, d, p)
                pkg(os.path.join(out, nm + ".docx"), body, compat)
                json.dump(meta, open(os.path.join(out, nm + ".meta"), "w"))
                print(nm, len(meta))
