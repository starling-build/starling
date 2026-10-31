#!/usr/bin/env python3
"""Lab nt1: where Word cuts a table nested in a one-row outer table at the page's foot (Linux lo5, 2026-10-30;
LibreOffice's fdo77887 / fdo48718-1: Word sets 44 rows of 9pt text on page 1 whose last row ends 25pt below the
bottom margin; ours stops at 42).
Page 12242 x 18722 twips, margins 1418 all round (top/bottom), 1701 left/right, no header or footer, compat 14.
The outer table: one row (trHeight atLeast 9016 twips unless 'short'), one cell, vAlign center, a one-line title
paragraph, then the nested table of 90 one-line rows 'R01'..'R90' (Arial 9pt, single, 0 spacing), then a closing paragraph.
Variants: b05 (nested borders 0.5pt), b00 (none), b30 (3pt), b05-short (no row minimum), b05-top (cell vAlign top),
b05-frame (every nested paragraph carries the framePr of the LibreOffice documents), flat-b05 (the same 90 rows as
a plain top-level table, 0.5pt: Word's ordinary cut).
usage: build.py OUTDIR.  Word for Windows -> PDF; report per document, page 1's last row (its text and y, PDF text top, pt),
the y of R01, and the page count."""
import os, sys, zipfile
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
RF = '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="18"/><w:szCs w:val="18"/>'
SP = '<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>'
FRAME = '<w:framePr w:hSpace="141" w:wrap="around" w:vAnchor="page" w:hAnchor="margin" w:xAlign="center" w:y="2266"/>'
def para(t, frame=False):
    return '<w:p><w:pPr>%s%s<w:rPr>%s</w:rPr></w:pPr><w:r><w:rPr>%s</w:rPr><w:t>%s</w:t></w:r></w:p>' % (FRAME if frame else '', SP, RF, RF, t)
def borders(sz):
    if sz == 0: return ''
    s = ''.join('<w:%s w:val="single" w:sz="%d" w:space="0" w:color="auto"/>' % (e, sz) for e in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'))
    return '<w:tblBorders>%s</w:tblBorders>' % s
def nested(sz, frame):
    rows = ''.join('<w:tr><w:tc><w:tcPr><w:tcW w:w="5000" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>%s</w:tc></w:tr>' % para('R%02d' % n, frame) for n in range(1, 91))
    return '<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="dxa"/><w:jc w:val="center"/>%s</w:tblPr><w:tblGrid><w:gridCol w:w="5000"/></w:tblGrid>%s</w:tbl>' % (borders(sz), rows)
def outer(inner, short, valign):
    h = '' if short else '<w:trHeight w:val="9016"/>'
    return ('<w:tbl><w:tblPr><w:tblW w:w="10081" w:type="dxa"/></w:tblPr><w:tblGrid><w:gridCol w:w="10081"/></w:tblGrid>'
            '<w:tr><w:trPr>%s</w:trPr><w:tc><w:tcPr><w:tcW w:w="10081" w:type="dxa"/><w:vAlign w:val="%s"/></w:tcPr>%s%s%s</w:tc></w:tr></w:tbl>'
            % (h, valign, para('TITLE'), inner, para('END')))
def doc(body):
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s<w:p/>'
            '<w:sectPr><w:pgSz w:w="12242" w:h="18722"/><w:pgMar w:top="1418" w:right="1701" w:bottom="1418" w:left="1701" w:header="709" w:footer="709" w:gutter="0"/></w:sectPr></w:body></w:document>' % (W, body))
CT = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
DRELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
         '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
SET = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings %s><w:compat><w:compatSetting w:name="compatibilityMode" '
       'w:uri="http://schemas.microsoft.com/office/word" w:val="14"/></w:compat></w:settings>' % W)
V = [('b05', 4, False, 'center', False), ('b00', 0, False, 'center', False), ('b30', 24, False, 'center', False),
     ('b05-short', 4, True, 'center', False), ('b05-top', 4, False, 'top', False), ('b05-frame', 4, False, 'center', True)]
for name, sz, short, va, fr in V:
    body = outer(nested(sz, fr), short, va)
    docs = [(name, body)]
    if name == 'b05':
        flat = nested(4, False).replace('<w:jc w:val="center"/>', '')
        docs.append(('flat-b05', flat))
    for n, b in docs:
        fn = os.path.join(out, 'nt1-%s.docx' % n)
        with zipfile.ZipFile(fn, 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS)
            z.writestr('word/_rels/document.xml.rels', DRELS); z.writestr('word/settings.xml', SET)
            z.writestr('word/document.xml', doc(b))
        print(fn)
