#!/usr/bin/env python3
"""Lab wsf (Windows 01QbbApP, for amd-opus): when do word spaces count as stretch and when do they give?  gen.py cal OUT | gen.py test OUT widths.json
Line = A + SPACES + B + X(工) + filler, 14pt 標楷體 eastAsia, zh-TW, jc both, compressPunctuation, exact 34pt, compat 15, no grid.
A = 12 ideographs, B = 12 ideographs ending in 移; k inner commas (0: none, 1: after A[5], 3: after A[5], A[11], B[5]).
Placements: f = s spaces between two ideographs  u = same, spaces underlined  i = Latin words 'Ab cd ef gh ij' (4 spaces) between ideographs (s=4 only).
space run font: t = ascii/hAnsi Times New Roman, no hint | k = ascii/hAnsi 標楷體, hint eastAsia.  balance (balanceSingleByteDoubleByteWidth) 1 / 0.
test: one paragraph per W, W stepped 0.5pt from natural(L+X)-14 to natural(L+X), right indent = text width - W."""
import sys, os, json, zipfile
A0 = "政府機關辦理考核成績優良"       # 12
B0 = "人員獎勵措施規定事項之移"       # 12, ends 移
FILL = "並應配合辦理相關事項之規定以維護公共衛生安全及保障全體民眾健康"
W_ = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
PLACE = [("f4", "f", 4), ("f8", "f", 8), ("u4", "u", 4), ("u8", "u", 8), ("i4", "i", 4)]
UL = '<w:u w:val="single"/>'


def split(k):
    a, b = A0, B0
    if k == 0:
        return [a, b]
    if k == 1:
        return [a[:6] + "，" + a[6:], b]
    return [a[:6] + "，" + a[6:12] + "，", b[:6] + "，" + b[6:]]


BASE = '<w:sz w:val="28"/><w:szCs w:val="28"/><w:lang w:eastAsia="zh-TW"/>'


def rp(font=None, u=False):
    if font == "t":
        f = '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="標楷體"/>'
    elif font == "k":
        f = '<w:rFonts w:ascii="標楷體" w:hAnsi="標楷體" w:eastAsia="標楷體" w:hint="eastAsia"/>'
    else:
        f = '<w:rFonts w:ascii="標楷體" w:hAnsi="標楷體" w:eastAsia="標楷體"/>'
    ul = UL if u else ""
    return '<w:rPr>' + f + ul + BASE + '</w:rPr>'


def run(t, font=None, u=False):
    return '<w:r>' + rp(font, u) + '<w:t xml:space="preserve">' + t + '</w:t></w:r>'


def line(pl, font, k, tail):
    kind, s = {p[0]: p[1:] for p in PLACE}[pl]
    a, b = split(k)
    if kind == "i":
        mid = run("Ab cd ef gh ij", font)
    else:
        mid = run(" " * s, font, kind == "u")
    return run(a) + mid + run(b + tail)


def para(runs, rind=0, jc="left"):
    return ('<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="680" w:lineRule="exact"/><w:ind w:left="0" w:right="%d"/><w:jc w:val="%s"/></w:pPr>%s</w:p>' % (rind, jc, runs))


def pkg(path, body, bal):
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="720" w:bottom="1440" w:left="720" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W_, body, sect)
    sty = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles %s><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="標楷體" w:hAnsi="標楷體" w:eastAsia="標楷體"/>%s</w:rPr></w:rPrDefault></w:docDefaults>'
           '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>' % (W_, BASE))
    bb = '<w:balanceSingleByteDoubleByteWidth/>' if bal else ''
    st = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings %s><w:characterSpacingControl w:val="compressPunctuation"/><w:compat>%s'
          '<w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>' % (W_, bb))
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
        for bal in (1, 0):
            for font in "tk":
                body = ""
                ks = []
                for pl, _, _ in PLACE:
                    for k in (0, 1, 3):
                        body += para(line(pl, font, k, "工"))
                        ks.append("%s-%d" % (pl, k))
                n = "cal-b%d%s" % (bal, font)
                pkg(os.path.join(out, n + ".docx"), body, bal)
                json.dump(ks, open(os.path.join(out, n + ".keys"), "w"))
                print(n)
    else:
        Wd = json.load(open(sys.argv[3]))   # {"b1t": {"f4-0": natural, ...}}
        for bal in (1, 0):
            for font in "tk":
                for pl, _, _ in PLACE:
                    body = ""
                    meta = []
                    for k in (0, 1, 3):
                        nat = Wd["b%d%s" % (bal, font)]["%s-%d" % (pl, k)]
                        for i in range(29):
                            w = nat - 14 + i * 0.5
                            body += para(line(pl, font, k, "工" + FILL), 10466 - round(w * 20), "both")
                            meta.append((k, w))
                    n = "wsf-b%d%s-%s" % (bal, font, pl)
                    pkg(os.path.join(out, n + ".docx"), body, bal)
                    json.dump(meta, open(os.path.join(out, n + ".meta"), "w"))
                    print(n, len(meta))
