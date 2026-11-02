#!/usr/bin/env python3
"""Lab stsp builder: does w:suppressTopSpacing raise the first exact-height line of a page? usage: build.py OUTDIR"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
#  code, exact line height pt, font size pt, suppressTopSpacing on?, space-before pt on first paragraph
V = []
for h, s in ((24, 12), (18, 12), (30, 12), (36, 12), (24, 10), (24, 14), (12, 12)):
    V.append((f"E{h}s{s}-off", h, s, False, 0))
    V.append((f"E{h}s{s}-on",  h, s, True,  0))
V.append(("E24s12-on-sb12", 24, 12, True, 12)); V.append(("E24s12-off-sb12", 24, 12, False, 12))
V.append(("AUTO12-on", 0, 12, True, 0)); V.append(("AUTO12-off", 0, 12, False, 0))
def para(n, h, s, sb):
    line = f'<w:spacing w:before="{int(sb*20)}" w:after="0" w:line="{h*20}" w:lineRule="exact"/>' if h else f'<w:spacing w:before="{int(sb*20)}" w:after="0"/>'
    return f'<w:p><w:pPr>{line}</w:pPr><w:r><w:rPr><w:sz w:val="{s*2}"/></w:rPr><w:t>BODY LINE {n}</w:t></w:r></w:p>'
def doc(h, s, sb):
    body = ''.join(para(i, h, s, sb if i == 1 else 0) for i in range(1, 5))
    sect = '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{body}{sect}</w:body></w:document>'
STYLES = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/></w:rPr></w:rPrDefault>'
          '<w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>')
def settings(on):
    flag = '<w:suppressTopSpacing/>' if on else ''
    return (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {NS}><w:compat>{flag}'
            '<w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>')
CT = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
DRELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
def main(out):
    os.makedirs(out, exist_ok=True)
    for n, (code, h, s, on, sb) in enumerate(V, 1):
        with zipfile.ZipFile(os.path.join(out, f"stsp-{n:02d}-{code}.docx"), "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
            z.writestr("word/document.xml", doc(h, s, sb)); z.writestr("word/styles.xml", STYLES)
            z.writestr("word/settings.xml", settings(on)); z.writestr("word/_rels/document.xml.rels", DRELS)
    print(len(V), "documents in", out)
if __name__ == "__main__": main(sys.argv[1])
