#!/usr/bin/env python3
"""Lab negtop builder: where Word puts the body when the top margin is NEGATIVE ("exact"), with a header that needs more. usage: build.py OUTDIR"""
import sys, os, zipfile
NS = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')
def hdr_para(before): return f'<w:p><w:pPr><w:spacing w:before="{before}" w:line="480" w:lineRule="exact"/></w:pPr><w:r><w:t>HEADER LINE</w:t></w:r></w:p>'
def hdr_small(before): return hdr_para(before)
def hdr_tall(before, height=14880):  # orrick's: an exact-height row, 744pt, one paragraph with the space before
    return (f'<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="dxa"/><w:tblLayout w:type="fixed"/></w:tblPr><w:tblGrid><w:gridCol w:w="5000"/></w:tblGrid>'
            f'<w:tr><w:trPr><w:trHeight w:hRule="exact" w:val="{height}"/></w:trPr><w:tc><w:tcPr><w:tcW w:w="5000" w:type="dxa"/></w:tcPr>'
            f'{hdr_para(before)}</w:tc></w:tr></w:tbl><w:p/>')
#  code, description, top twips, header-distance twips, header body or None
V = [
 ("N1", "CONTROL top +1327, short header (space before 720)",           1327, 431, lambda: hdr_small(720)),
 ("N2", "top -1327, short header (space before 720)",                    -1327, 431, lambda: hdr_small(720)),
 ("N3", "top -1327, short header, space before 0",                       -1327, 431, lambda: hdr_small(0)),
 ("N4", "top -1327, NO header at all",                                   -1327, 431, None),
 ("N5", "top -1327, tall exact-row header (744pt), space before 720",    -1327, 431, lambda: hdr_tall(720)),
 ("N6", "CONTROL top +1327, tall exact-row header",                      1327, 431, lambda: hdr_tall(720)),
 ("N7", "top -1327, short header, header distance 0, space before 720",  -1327, 0,   lambda: hdr_small(720)),
 ("N8", "top -600, short header (space before 720)",                     -600, 431,  lambda: hdr_small(720)),
 ("N9", "top -1327, tall exact-row header, space before 0",              -1327, 431, lambda: hdr_tall(0)),
 ("N10", "top -1327, tall exact-row header, header distance 1440, space before 720", -1327, 1440, lambda: hdr_tall(720)),
]
def body_para(n): return f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="480" w:lineRule="exact"/></w:pPr><w:r><w:t>BODY LINE {n}</w:t></w:r></w:p>'
def doc(code, top, hd, hfn):
    body = ''.join(body_para(i) for i in range(1, 6))
    href = '<w:headerReference w:type="default" r:id="rId3"/>' if hfn else ''
    sect = (f'<w:sectPr>{href}<w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="{top}" w:right="1440" w:bottom="1440" w:left="1440" '
            f'w:header="{hd}" w:footer="720" w:gutter="0"/><w:cols w:space="720"/></w:sectPr>')
    document = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{body}{sect}</w:body></w:document>'
    header = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:hdr {NS}>{hfn()}</w:hdr>' if hfn else None
    styles = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr>'
              '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/></w:rPr></w:rPrDefault>'
              '<w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
              '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>')
    settings = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {NS}><w:compat>'
                '<w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>')
    return document, header, styles, settings
CT = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/><Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/></Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
def drels(has_header):
    h = '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>' if has_header else ''
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>' + h + '</Relationships>')
def main(out):
    os.makedirs(out, exist_ok=True)
    for n, (code, desc, top, hd, hfn) in enumerate(V, 1):
        d, h, s, st = doc(code, top, hd, hfn)
        with zipfile.ZipFile(os.path.join(out, f"negtop-{n:02d}-{code}.docx"), "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
            z.writestr("word/document.xml", d); z.writestr("word/styles.xml", s); z.writestr("word/settings.xml", st)
            z.writestr("word/_rels/document.xml.rels", drels(bool(h)))
            if h: z.writestr("word/header1.xml", h)
    print(len(V), "documents in", out)
if __name__ == "__main__":
    main(sys.argv[1])
