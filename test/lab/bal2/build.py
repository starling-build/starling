#!/usr/bin/env python3
"""Lab bal (Windows 01QbbApP, for amd-5): gap between a Latin/digit run and an ideograph with balanceSingleByteDoubleByteWidth.
bal-on / bal-off: compat 15, characterSpacingControl compressPunctuation, zh-TW, 標楷體 eastAsia + Times New Roman ascii/hAnsi, jc left, no grid.
Each doc: the 6 strings at 14pt then at 10.5pt, one paragraph each (spacing 0, single). usage: build.py OUTDIR"""
import sys, os, zipfile
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
STR = [("a", "除PCR檢"), ("b", "19疫"), ("c", "第5點"), ("d", "疫 19疫"), ("e", "除 PCR 檢")]
SIZES = (14,)

def para(t, sz, kern=0):
    h = int(sz * 2)
    K = '<w:kern w:val="0"/>' if kern else ''
    return (f'<w:p><w:pPr><w:jc w:val="left"/><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>'
            f'<w:r><w:rPr>{K}<w:sz w:val="{h}"/><w:szCs w:val="{h}"/></w:rPr><w:t xml:space="preserve">{t}</w:t></w:r></w:p>')

def build(path, bal, kern=0, grid=0):
    body = ''.join(para(t, s, kern) for s in SIZES for _, t in STR)
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>' + ('<w:docGrid w:type="lines" w:linePitch="360"/>' if grid else '') + '</w:sectPr>'
    document = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{body}{sect}</w:body></w:document>'
    styles = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {W}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="標楷體" w:hAnsi="標楷體" w:eastAsia="標楷體" w:cs="Times New Roman"/>'
              '<w:sz w:val="28"/><w:szCs w:val="28"/><w:lang w:val="en-US" w:eastAsia="zh-TW"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
              '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>')
    settings = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {W}><w:characterSpacingControl w:val="compressPunctuation"/><w:compat>'
                + ('<w:balanceSingleByteDoubleByteWidth/>' if bal else '') +
                '<w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>')
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
          '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
    root = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
    drels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
             '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
             '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, v in (("[Content_Types].xml", ct), ("_rels/.rels", root), ("word/document.xml", document), ("word/styles.xml", styles), ("word/settings.xml", settings), ("word/_rels/document.xml.rels", drels)):
            z.writestr(n, v)

if __name__ == "__main__":
    os.makedirs(sys.argv[1], exist_ok=True)
    for name, bal, kern, grid in (("bal2-plain", 1, 0, 0), ("bal2-kern0", 1, 1, 0), ("bal2-kern0-grid", 1, 1, 1), ("bal2-off-plain", 0, 0, 0)):
        build(os.path.join(sys.argv[1], name + ".docx"), bal, kern, grid); print(name)
