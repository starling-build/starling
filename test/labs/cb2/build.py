#!/usr/bin/env python3
"""Lab cb2 builder: where the paragraph after a column-break paragraph stands. usage: build.py OUTDIR"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
BR = '<w:r><w:br w:type="column"/></w:r>'
def p(text="", ppr="", extra="", rpr=""):
    r = f'<w:r><w:rPr>{rpr}</w:rPr><w:t>{text}</w:t></w:r>' if text else ''
    return f'<w:p><w:pPr>{ppr}</w:pPr>{r}{extra}</w:p>'
SP = '<w:spacing w:before="100" w:after="0"/><w:ind w:firstLine="840"/>'            # zh-6cd1befe's break paragraph
TINY = '<w:spacing w:line="14" w:lineRule="auto"/><w:rPr><w:sz w:val="2"/></w:rPr>'  # zh-8f9b19f4's break paragraph
TINYBR = '<w:r><w:rPr><w:sz w:val="2"/></w:rPr><w:br w:type="column"/></w:r>'
HEAD = '<w:spacing w:before="240" w:after="0"/>'                                      # a heading: 12pt space before
HEADL = '<w:spacing w:before="240" w:beforeLines="100" w:after="0"/>'                 # as zh-6cd1befe's: beforeLines too
V = [  # (code, description, body before B, B paragraph ppr, B run props)
 ("W1", "V1 shape: text, empty break paragraph; B has 12pt space before, 22pt", lambda n: p(f"A{n}") + p("", "", BR), HEAD, '<w:sz w:val="44"/>'),
 ("W2", "V3 shape (5pt before + first-line indent) break paragraph; B 12pt before, 22pt", lambda n: p(f"A{n}") + p("", SP, BR), HEAD, '<w:sz w:val="44"/>'),
 ("W3", "as W2 and B states beforeLines=100 too (zh-6cd1befe's heading)", lambda n: p(f"A{n}") + p("", SP, BR), HEADL, '<w:sz w:val="44"/>'),
 ("W4", "V1 shape; B plain 12pt, NO space before (control: cb1's V1)", lambda n: p(f"A{n}") + p("", "", BR), '', ''),
 ("W5", "break paragraph of 1pt font and a 0.7pt auto line (zh-8f9b19f4's); B with 4.9pt before", lambda n: p(f"A{n}") + f'<w:p><w:pPr>{TINY}</w:pPr>{TINYBR}</w:p>', '<w:spacing w:before="98" w:after="0"/>', ''),
 ("W6", "as W5; B plain, no space before", lambda n: p(f"A{n}") + f'<w:p><w:pPr>{TINY}</w:pPr>{TINYBR}</w:p>', '', ''),
 ("W7", "A line is an exact 26pt line; V1 break paragraph; B 12pt before", lambda n: p(f"A{n}", '<w:spacing w:line="520" w:lineRule="exact"/>') + p("", "", BR), HEAD, '<w:sz w:val="44"/>'),
 ("W8", "text and break in ONE paragraph (cb1's V4); B 12pt before", lambda n: p(f"A{n}", "", BR), HEAD, '<w:sz w:val="44"/>'),
]
def doc(mode, cols_xml, grid):
    body = ''
    for i, (code, desc, fn, bppr, brpr) in enumerate(V, 1):
        sect = (f'<w:sectPr><w:type w:val="nextPage"/><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="851" w:footer="992" w:gutter="0"/>'
                f'{cols_xml}{grid}</w:sectPr>')
        b = fn(code)
        after = p(f"B{code}", bppr, "", brpr)
        if i == len(V): body += b + after
        else: body += b + after + f'<w:p><w:pPr>{sect}</w:pPr></w:p>'
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
    narrow = '<w:cols w:equalWidth="0" w:num="2"><w:col w:w="1272" w:space="312"/><w:col w:w="7000"/></w:cols>'
    n = 0
    for mode in (14, 15):
        for cname, g in (("narrow", ""), ("narrowgrid286", '<w:docGrid w:linePitch="286" w:charSpace="0"/>')):
            n += 1
            d, s, st = doc(mode, narrow, g)
            fn = os.path.join(out, f"cb2-{n:02d}-m{mode}-{cname}.docx")
            with zipfile.ZipFile(fn, "w", zipfile.ZIP_DEFLATED) as z:
                z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
                z.writestr("word/document.xml", d); z.writestr("word/styles.xml", s); z.writestr("word/settings.xml", st)
                z.writestr("word/_rels/document.xml.rels", DRELS)
    print(n, "documents in", out)
if __name__ == "__main__":
    main(sys.argv[1])
