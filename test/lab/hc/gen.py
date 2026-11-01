#!/usr/bin/env python3
"""Lab hc (Windows 01QbbApP, for amd-5): does Word take X + hung comma when a justified line is a few pt short?
gen.py cal OUT | gen.py test OUT widths.json.  Line L = zh-6d402586's line ending at 移; next chars 工， then filler. Variants:
 A: as is (two inner commas), compressPunctuation | B: inner commas removed | C: as A with doNotCompress.
14pt 標楷體 (also the Latin), balance ON, compat 15, jc both, exact line 34pt. test: one paragraph per measure W (right indent), W stepped 1pt."""
import sys, os, json, zipfile
A_ = "COVID-19疫苗者，得免除PCR檢驗，未完整接種疫苗之移"
B_ = "COVID-19疫苗者得免除PCR檢驗未完整接種疫苗之移"
FILL = "工，並應配合辦理相關事項之規定以維護公共衛生安全及保障全體民眾健康"
W_ = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
VAR = {"A": (A_, "compressPunctuation"), "B": (B_, "compressPunctuation"), "C": (A_, "doNotCompress")}
def para(t, rind=0, jc="left"):
    return (f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="680" w:lineRule="exact"/><w:ind w:left="0" w:right="{rind}"/><w:jc w:val="{jc}"/></w:pPr>'
            f'<w:r><w:rPr><w:rFonts w:ascii="標楷體" w:hAnsi="標楷體" w:eastAsia="標楷體"/><w:sz w:val="28"/><w:szCs w:val="28"/><w:lang w:eastAsia="zh-TW"/></w:rPr><w:t xml:space="preserve">{t}</w:t></w:r></w:p>')
def pkg(path, body, csc):
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    doc = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W_}><w:body>{body}{sect}</w:body></w:document>'
    sty = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {W_}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="標楷體" w:hAnsi="標楷體" w:eastAsia="標楷體"/><w:sz w:val="28"/><w:szCs w:val="28"/><w:lang w:val="en-US" w:eastAsia="zh-TW"/></w:rPr></w:rPrDefault></w:docDefaults>'
           '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>')
    st = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {W_}><w:characterSpacingControl w:val="{csc}"/><w:compat><w:balanceSingleByteDoubleByteWidth/>'
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
    if mode == "cal":
        for v, (L, csc) in VAR.items():
            pkg(os.path.join(out, f"cal-{v}.docx"), para(L) + para(L + "工") + para(L + "工，"), csc); print("cal-" + v)
    else:
        W = json.load(open(sys.argv[3]))
        for v, (L, csc) in VAR.items():
            lo, hi = W[v]["L"], W[v]["Lgc"]
            body = ""; ws = []
            w = int(lo) - 3
            while w <= hi + 4:
                ws.append(w); body += para(L + FILL, 9026 - round(w * 20), "both"); w += 1
            pkg(os.path.join(out, f"hc-{v}.docx"), body, csc); json.dump(ws, open(os.path.join(out, f"hc-{v}.ws"), "w")); print("hc-" + v, len(ws))
