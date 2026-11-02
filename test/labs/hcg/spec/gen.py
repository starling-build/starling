#!/usr/bin/env python3
"""Lab hcg (Windows 01QbbApP, for amd-opus): is the doubled autospace weight from the hang or from the balance setting?
gen.py cal OUT | gen.py test OUT widths.json.  Lines (hc3 naming): d = no inner comma, a = one inner comma, A = two (hc.A_), each with the
autospaces COVID-19|疫 and 檢|PCR style boundaries. X = 工. follow: c = 工，  p = 工並 (plain ideograph, no hang)  s = 工；
Factors: balance on/off (compat balanceSingleByteDoubleByteWidth), Latin face 標楷體 (K) / Times New Roman (T).
14pt, zh-TW, jc both, compressPunctuation, exact 34pt, compat 15. test: one paragraph per W (right indent), W stepped 1pt."""
import sys, os, json, zipfile
A_ = "COVID-19疫苗者，得免除PCR檢驗，未完整接種疫苗之移"
LINES = {"d": "COVID-19疫苗者得免除PCR檢驗未完整接種疫苗之移",
         "a": "COVID-19疫苗者，得免除PCR檢驗未完整接種疫苗之移",
         "A": A_}
TAIL = {"c": "工，", "p": "工並", "s": "工；"}
FILL = "應配合辦理相關事項之規定以維護公共衛生安全及保障全體民眾健康"
W_ = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
def rpr(face):
    lat = "標楷體" if face == "K" else "Times New Roman"
    return f'<w:rFonts w:ascii="{lat}" w:hAnsi="{lat}" w:eastAsia="標楷體"/><w:sz w:val="28"/><w:szCs w:val="28"/><w:lang w:eastAsia="zh-TW"/>'
def para(t, face, rind=0, jc="left"):
    return (f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="680" w:lineRule="exact"/><w:ind w:left="0" w:right="{rind}"/><w:jc w:val="{jc}"/></w:pPr>'
            f'<w:r><w:rPr>{rpr(face)}</w:rPr><w:t xml:space="preserve">{t}</w:t></w:r></w:p>')
def pkg(path, body, bal, face):
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    doc = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W_}><w:body>{body}{sect}</w:body></w:document>'
    sty = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {W_}><w:docDefaults><w:rPrDefault><w:rPr>{rpr(face)}</w:rPr></w:rPrDefault></w:docDefaults>'
           '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>')
    b = '<w:balanceSingleByteDoubleByteWidth/>' if bal else ''
    st = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {W_}><w:characterSpacingControl w:val="compressPunctuation"/><w:compat>{b}'
          '<w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>')
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
    root = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    dr = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, v in (("[Content_Types].xml", ct), ("_rels/.rels", root), ("word/document.xml", doc), ("word/styles.xml", sty), ("word/settings.xml", st), ("word/_rels/document.xml.rels", dr)): z.writestr(n, v)
if __name__ == "__main__":
    mode, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
    combos = [(bal, face) for bal in (1, 0) for face in "KT"]
    if mode == "cal":
        keys = []
        for bal, face in combos:
            body = ""; ks = []
            for l, L in LINES.items():
                body += para(L, face); ks.append((l, "L"))
                for t, x in TAIL.items(): body += para(L + x, face); ks.append((l, t))
            n = f"cal-b{bal}{face}"; pkg(os.path.join(out, n + ".docx"), body, bal, face); json.dump(ks, open(os.path.join(out, n + ".keys"), "w")); print(n)
    else:
        W = json.load(open(sys.argv[3]))   # {"b1K": {"d": [lo, hi], ...}}
        for bal, face in combos:
            for l, L in LINES.items():
                lo, hi = W[f"b{bal}{face}"][l]; ws = list(range(int(lo) - 3, int(hi) + 5))
                body = ""; meta = []
                for t, x in TAIL.items():
                    for w in ws: body += para(L + x + FILL, face, 9026 - round(w * 20), "both"); meta.append((t, w))
                n = f"hcg-b{bal}{face}-{l if l != chr(65) else '2c'}"; pkg(os.path.join(out, n + ".docx"), body, bal, face); json.dump(meta, open(os.path.join(out, n + ".meta"), "w")); print(n, len(meta))
