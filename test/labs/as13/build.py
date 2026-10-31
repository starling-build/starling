#!/usr/bin/env python3
"""Lab as13: a paragraph holding ONLY a page break (w:br type=page) at the foot of a page, with
less than one line of room left, followed by (a) a floating table, (b) an ordinary table, (c) text.
Question (LibreOffice's floattable-header): Word puts the table on page 2 under ONE empty line (the
break paragraph's mark), where the 'gf' lab says a break line with no room takes a page of its own
(a blank page) and the text after it goes to page 3.
Page A4 (841.9pt), margins 72pt: a body of 697.9pt. One filler paragraph of exact line height leaves
R points: R=100 (control: the break line fits), 20 (fits, a 13.8pt line), 10, 3 (it does not).
usage: build.py OUTDIR      Word for Windows -> PDF; report, per document, the PAGE and y (PDF text
top, pt) of the words FILL, TABLE (or TEXT) and ANCHOR."""
import os, sys, zipfile

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
W = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
     'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')
BODY = 841.9 - 144.0

def filler(room):
    h = int(round((BODY - room) * 20))
    return ('<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="%d" w:lineRule="exact"/></w:pPr>'
            '<w:r><w:t>FILL</w:t></w:r></w:p>' % h)

BREAK = '<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr><w:r><w:br w:type="page"/></w:r></w:p>'
def para(t): return '<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr><w:r><w:t>%s</w:t></w:r></w:p>' % t
def table(floating):
    pos = '<w:tblpPr w:leftFromText="180" w:rightFromText="180" w:vertAnchor="text" w:tblpY="1"/><w:tblOverlap w:val="never"/>' if floating else ''
    return ('<w:tbl><w:tblPr>%s<w:tblW w:w="4000" w:type="dxa"/><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
            '<w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
            '<w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/></w:tblBorders></w:tblPr><w:tblGrid><w:gridCol w:w="4000"/></w:tblGrid>'
            '<w:tr><w:tc><w:tcPr><w:tcW w:w="4000" w:type="dxa"/></w:tcPr>%s</w:tc></w:tr></w:tbl>' % (pos, para('TABLE')))

def doc(room, kind):
    body = filler(room) + BREAK
    if kind == 'floating': body += table(True) + para('ANCHOR')
    elif kind == 'table': body += table(False) + para('ANCHOR')
    else: body += para('TEXT') + para('ANCHOR')
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s'
            '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
            'w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>' % (W, body))

CT = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
DRELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
         '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
SET = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings %s><w:compat><w:compatSetting w:name="compatibilityMode" '
       'w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>' % W)

for room in (100, 20, 10, 3):
    for kind in ('floating', 'table', 'text'):
        fn = os.path.join(out, 'as13-R%d-%s.docx' % (room, kind))
        with zipfile.ZipFile(fn, 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS)
            z.writestr('word/_rels/document.xml.rels', DRELS); z.writestr('word/settings.xml', SET)
            z.writestr('word/document.xml', doc(room, kind))
        print(fn)
