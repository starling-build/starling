#!/usr/bin/env python3
"""Lab ft2 (Windows 01QbbApP, for lenovo-3): blank paragraphs under a text-anchored floating table.
Table tblpPr L/R 141 vertAnchor=text horzAnchor=page tblpX 2352 tblpY (335|0), tblW 8008 fixed, cell margins L/R 70, one row trHeight 1271 atLeast,
single sz4 borders, 8 lines Arial 12.  Top margin 2613 twips (130.65pt).  A,B,C = paragraphs with ind 0, jc both, mark Arial 12 bold + single underline.
gen.py OUT : v1 A,B,text | v2 A,text | v3 A,B,C,text | v4 A,'B' word,text | v5 = v1 with tblpY 0"""
import sys, os, zipfile
W_ = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
RP = '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="24"/>'
MK = '<w:rPr>' + RP + '<w:b/><w:u w:val="single"/></w:rPr>'


def blank():
    return '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/><w:ind w:left="0" w:firstLine="0"/><w:jc w:val="both"/>%s</w:pPr></w:p>' % MK


def word(t):
    return '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/><w:ind w:left="0" w:firstLine="0"/><w:jc w:val="both"/>%s</w:pPr><w:r>%s<w:t>%s</w:t></w:r></w:p>' % (MK, MK, t)


def text(t):
    return '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:rPr>%s</w:rPr><w:t>%s</w:t></w:r></w:p>' % (RP, t)


def tbl(y):
    tp = '<w:tblpPr w:leftFromText="141" w:rightFromText="141" w:vertAnchor="text" w:horzAnchor="page" w:tblpX="2352" w:tblpY="%d"/>' % y
    b = ''.join('<w:%s w:val="single" w:sz="4" w:space="0" w:color="000000"/>' % s for s in ("top", "left", "bottom", "right"))
    cell = ''.join(text("Table line %d" % i) for i in range(1, 9))
    return ('<w:tbl><w:tblPr>%s<w:tblW w:w="8008" w:type="dxa"/><w:tblBorders>%s</w:tblBorders><w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="70" w:type="dxa"/><w:right w:w="70" w:type="dxa"/></w:tblCellMar></w:tblPr>'
            '<w:tblGrid><w:gridCol w:w="8008"/></w:tblGrid><w:tr><w:trPr><w:trHeight w:val="1271" w:hRule="atLeast"/></w:trPr><w:tc><w:tcPr><w:tcW w:w="8008" w:type="dxa"/></w:tcPr>%s</w:tc></w:tr></w:tbl>' % (tp, b, cell))


def pkg(path, body):
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="2613" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W_, body, sect)
    sty = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles %s><w:docDefaults><w:rPrDefault><w:rPr>%s</w:rPr></w:rPrDefault></w:docDefaults>'
           '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>' % (W_, RP))
    st = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings %s><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>' % W_)
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
    root = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    dr = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, v in (("[Content_Types].xml", ct), ("_rels/.rels", root), ("word/document.xml", doc), ("word/styles.xml", sty), ("word/settings.xml", st), ("word/_rels/document.xml.rels", dr)):
            z.writestr(n, v)


T = lambda: text("TEXTLINE")
V = {
    "v1": (335, lambda: blank() + blank() + T()),
    "v2": (335, lambda: blank() + T()),
    "v3": (335, lambda: blank() + blank() + blank() + T()),
    "v4": (335, lambda: blank() + word("BBB") + T()),
    "v5": (0, lambda: blank() + blank() + T()),
}
if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for n, (y, f) in V.items():
        pkg(os.path.join(out, "ft2-%s.docx" % n), tbl(y) + f())
        print(n)
