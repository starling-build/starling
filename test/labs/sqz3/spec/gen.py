#!/usr/bin/env python3
"""Lab sqz3 (Word for Windows, for amd-3): why does Word take or refuse ONE ideograph past half an em at a line end?
Fit-log census (633 docs): justified, mode 14, 4+ given spaces, lone ideograph, need within room: Word takes 6, refuses 241 with the same numbers;
left-aligned, 1-2 given spaces, need over room: takes 2, refuses 44. Candidates the log does not record: the character after, the previous line, mode.
gen.py test OUT: one file per variant, 43 paragraphs each, W stepped 0.5pt over the 21pt below the natural width of  A + spaces + B + X.
Line = A(12 ideographs) + S spaces + B(12 ideographs) + X(工) + NEXT + FILL, 14pt 標楷體, zh-TW, compressPunctuation, exact 34pt, no grid.
Variants: S in 0,2,4 (spaces between ideographs) x jc both|left x compat 14|15 x NEXT = ideograph | digit 1 | '(' | closing mark '，'.
Natural width is not calibrated: A+B+X = 25 x 14pt, spaces taken as 7pt; the read-out is the first W at which 工 stays (meas.py of lab wsf reads x positions)."""
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


def lineX(S, nxt):
    return run(A0) + run(" " * S, "k") + run(B0 + "工" + nxt + FILL)


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


def pkg(path, body, bal, mode=15):
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="720" w:bottom="1440" w:left="720" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W_, body, sect)
    sty = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles %s><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="標楷體" w:hAnsi="標楷體" w:eastAsia="標楷體"/>%s</w:rPr></w:rPrDefault></w:docDefaults>'
           '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>' % (W_, BASE))
    bb = '<w:balanceSingleByteDoubleByteWidth/>' if bal else ''
    st = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings %s><w:characterSpacingControl w:val="compressPunctuation"/><w:compat>%s'
          '<w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="%d"/></w:compat></w:settings>' % (W_, bb, mode))
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
    root = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    dr = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, v in (("[Content_Types].xml", ct), ("_rels/.rels", root), ("word/document.xml", doc), ("word/styles.xml", sty), ("word/settings.xml", st), ("word/_rels/document.xml.rels", dr)):
            z.writestr(n, v)


if __name__ == "__main__":
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for S in (0, 2, 4):
        for jc in ("both", "left"):
            for mode in (14, 15):
                for nn, nxt in (("i", "一"), ("d", "1"), ("p", "("), ("c", "，")):
                    nat = 25 * 14 + 7 * S
                    body = ""; meta = []
                    for i in range(43):
                        w = nat - 21 + i * 0.5
                        body += para(lineX(S, nxt), 10466 - round(w * 20), jc)
                        meta.append(w)
                    n = "sqz3-s%d-%s-m%d-%s" % (S, jc, mode, nn)
                    pkg(os.path.join(out, n + ".docx"), body, 1, mode)
                    json.dump(meta, open(os.path.join(out, n + ".meta"), "w"))
                    print(n, len(meta))
