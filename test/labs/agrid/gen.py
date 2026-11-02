#!/usr/bin/env python3
"""Lab agrid (Windows 01QbbApP, for amd-opus): width of the automatic space beside a digit on a character grid.
Base: zh-9c162f26 (compat 14, compressPunctuation, useFELayout, docGrid linesAndChars linePitch 579, Normal sz 21 / 宋体 eastAsia, TNR ascii runs).
Lines left aligned (jc left), A4, margins top 2098 right 1474 bottom 1928 left 1587.
Cross: run size 9 / 10.5 / 12 x charSpace -842 / 0 / +1000 / no grid (Normal 10.5); plus Normal 10.5 / 12 at -842 and run 9.
Paragraphs: 1 single digit, 2 typed space after digit, 3 two digits, 4 typed space before and after, 5 digit at line start-ish control.
gen.py OUT"""
import sys, os, zipfile
W_ = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
LINES = [
    '每年活化1次蓄电池；每周巡视1次',
    '每年活化1 次蓄电池；每周巡视1 次',
    '每年活化12次蓄电池；每周巡视12次',
    '每年活化 1 次蓄电池；每周巡视 1 次',
    '每年活化次蓄电池；每周巡视次',
]


def run(t, sz2):
    rpr = ('<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:color w:val="000000"/><w:sz w:val="%d"/><w:szCs w:val="%d"/>' % (sz2, sz2))
    return '<w:r><w:rPr>%s</w:rPr><w:t xml:space="preserve">%s</w:t></w:r>' % (rpr, t)


def pkg(path, sz2, cs, nsz2):
    body = ''
    for t in LINES:
        body += '<w:p><w:pPr><w:jc w:val="left"/></w:pPr>%s</w:p>' % run(t, sz2)
    if cs is None:
        grid = ''
    else:
        grid = '<w:docGrid w:type="linesAndChars" w:linePitch="579" w:charSpace="%d"/>' % cs
    sect = ('<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="2098" w:right="1474" w:bottom="1928" w:left="1587" w:header="851" w:footer="1701" w:gutter="0"/>%s</w:sectPr>' % grid)
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W_, body, sect)
    sty = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles %s><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体" w:cs="Times New Roman"/></w:rPr></w:rPrDefault><w:pPrDefault/></w:docDefaults>'
           '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/><w:pPr><w:widowControl w:val="0"/><w:jc w:val="both"/></w:pPr>'
           '<w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="宋体" w:cs="宋体"/><w:kern w:val="2"/><w:sz w:val="%d"/><w:szCs w:val="24"/><w:lang w:val="en-US" w:eastAsia="zh-CN" w:bidi="ar-SA"/></w:rPr></w:style></w:styles>' % (W_, nsz2))
    st = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings %s><w:characterSpacingControl w:val="compressPunctuation"/><w:compat><w:useFELayout/>'
          '<w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="14"/></w:compat></w:settings>' % W_)
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
    root = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    dr = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        for n, v in (('[Content_Types].xml', ct), ('_rels/.rels', root), ('word/document.xml', doc), ('word/styles.xml', sty), ('word/settings.xml', st), ('word/_rels/document.xml.rels', dr)):
            z.writestr(n, v)


if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    CS = {'m842': -842, 'z0': 0, 'p1000': 1000, 'nogrid': None}
    for rs, rname in ((18, '9'), (21, '105'), (24, '12')):
        for cn, cs in CS.items():
            pkg(os.path.join(out, 'ag-r%s-%s-n105.docx' % (rname, cn)), rs, cs, 21)
    for nn, nname in ((21, '105'), (24, '12')):
        pkg(os.path.join(out, 'ag-r9-m842-n%s.docx' % nname), 18, -842, nn)
    print('ok')
