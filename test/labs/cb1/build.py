#!/usr/bin/env python3
"""Lab cb1 builder: where a column-break paragraph's own mark goes. usage: build.py OUTDIR"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
BR = '<w:r><w:br w:type="column"/></w:r>'
def p(text="", ppr="", extra=""):
    r = f'<w:r><w:t>{text}</w:t></w:r>' if text else ''
    return f'<w:p><w:pPr>{ppr}</w:pPr>{r}{extra}</w:p>'
def table():
    b = ''.join(f'<w:{s} w:val="single" w:sz="4" w:space="0" w:color="auto"/>' for s in ("top","left","bottom","right","insideH","insideV"))
    return (f'<w:tbl><w:tblPr><w:tblW w:w="3000" w:type="dxa"/><w:tblBorders>{b}</w:tblBorders></w:tblPr><w:tblGrid><w:gridCol w:w="3000"/></w:tblGrid>'
            f'<w:tr><w:trPr><w:trHeight w:val="700" w:hRule="atLeast"/></w:trPr><w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr>{p("cell")}</w:tc></w:tr></w:tbl>')
SP = '<w:spacing w:before="100" w:after="0"/><w:ind w:firstLine="840"/>'   # zh-6cd1befe's break paragraph
V = [  # (code, description, builder(n) -> body xml before B)
 ("V1", "text paragraph, then an empty paragraph holding only the column break", lambda n: p(f"A{n}") + p("", "", BR)),
 ("V2", "a table, then the empty break paragraph (tdf165492)", lambda n: p(f"A{n}") + table() + p("", "", BR)),
 ("V3", "text, then the break paragraph with space before 5pt and a first-line indent", lambda n: p(f"A{n}") + p("", SP, BR)),
 ("V4", "text and the column break in ONE paragraph, nothing after the break", lambda n: p(f"A{n}", "", BR)),
 ("V5", "break paragraph with an exact 26pt line", lambda n: p(f"A{n}") + p("", '<w:spacing w:line="520" w:lineRule="exact"/>', BR)),
 ("V6", "break paragraph with 12pt space after", lambda n: p(f"A{n}") + p("", '<w:spacing w:after="240"/>', BR)),
 ("V7", "break paragraph centred, 18pt font", lambda n: p(f"A{n}") + f'<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:sz w:val="36"/></w:rPr><w:br w:type="column"/></w:r></w:p>'),
 ("V8", "break paragraph followed by B in a table cell", lambda n: p(f"A{n}") + p("", "", BR)),
]
def doc(mode, cols_xml, grid):
    body = ''
    for i, (code, desc, fn) in enumerate(V, 1):
        sect = (f'<w:sectPr><w:type w:val="nextPage"/><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="851" w:footer="992" w:gutter="0"/>'
                f'{cols_xml}{grid}</w:sectPr>')
        b = fn(code)
        after = p(f"B{code}")
        if code == "V8":
            after = ('<w:tbl><w:tblPr><w:tblW w:w="2000" w:type="dxa"/></w:tblPr><w:tblGrid><w:gridCol w:w="2000"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="2000" w:type="dxa"/></w:tcPr>'
                     + p("BV8") + '</w:tc></w:tr></w:tbl>' + p(""))
        last = i == len(V)
        if last:
            body += b.replace(f"A{code}", f"A{code}") + after
        else:
            body += b + after + f'<w:p><w:pPr>{sect}</w:pPr></w:p>'
    final = (f'<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="851" w:footer="992" w:gutter="0"/>{cols_xml}{grid}</w:sectPr>')
    document = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{body}{final}</w:body></w:document>'
    styles = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="SimSun" w:cs="Arial"/><w:sz w:val="24"/></w:rPr></w:rPrDefault>'
              '<w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
              '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>')
    settings = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {NS}><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="{mode}"/></w:compat></w:settings>')
    return document, styles, settings
CT = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
DRELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
def main(out):
    os.makedirs(out, exist_ok=True)
    two = '<w:cols w:num="2" w:space="720"/>'
    narrow = '<w:cols w:equalWidth="0" w:num="2"><w:col w:w="1272" w:space="312"/><w:col w:w="7000"/></w:cols>'
    one = '<w:cols w:num="1" w:space="720"/>'
    grid = '<w:docGrid w:type="lines" w:linePitch="312"/>'
    n = 0
    for mode in (14, 15):
        for cname, cx, g in (("two", two, ""), ("narrow", narrow, ""), ("twogrid", two, grid), ("onecol", one, "")):
            n += 1
            d, s, st = doc(mode, cx, g)
            fn = os.path.join(out, f"cb1-{n:02d}-m{mode}-{cname}.docx")
            with zipfile.ZipFile(fn, "w", zipfile.ZIP_DEFLATED) as z:
                z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
                z.writestr("word/document.xml", d); z.writestr("word/styles.xml", s); z.writestr("word/settings.xml", st)
                z.writestr("word/_rels/document.xml.rels", DRELS)
    print(n, "documents in", out)
if __name__ == "__main__":
    main(sys.argv[1])
