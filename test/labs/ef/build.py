#!/usr/bin/env python3
"""build.py -> ef1.docx and ef2.docx (amd-3, for lo-eb12e7d4 p14): a picture on a line of 1.5 spacing, then an empty
paragraph of 1.5 spacing, at the foot of a column (ef2: two columns, ef1: one). The picture's height steps, so the
room left under its line steps; where does the empty paragraph go, and where is TAIL?  Needs PIL."""
import zipfile, sys, io
from PIL import Image
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
EMU = 12700
SP1 = '<w:spacing w:after="0" w:line="240" w:lineRule="auto"/>'
SP15 = '<w:spacing w:after="0" w:line="360" w:lineRule="auto"/>'
FONT = '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="20"/>'
def run(t): return '<w:r><w:rPr>%s</w:rPr><w:t xml:space="preserve">%s</w:t></w:r>' % (FONT, t)
def para(t, sp=SP1, extra='', ppr=''): return '<w:p><w:pPr>%s%s<w:rPr>%s</w:rPr></w:pPr>%s%s</w:p>' % (sp, ppr, FONT, run(t) if t else '', extra)
_id = [0]
def inline(w, h):
    _id[0] += 1
    g = ('<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="%d" name="p%d"/><pic:cNvPicPr/></pic:nvPicPr>'
         '<pic:blipFill><a:blip r:embed="rId2"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="%d" cy="%d"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic>') % (_id[0], _id[0], w * EMU, h * EMU)
    return '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="%d" cy="%d"/><wp:docPr id="%d" name="i%d"/>%s</wp:inline></w:drawing></w:r>' % (w * EMU, h * EMU, _id[0] + 100, _id[0], g)
def sect(cols):
    c = '<w:cols w:num="2" w:space="40"/>' if cols == 2 else '<w:cols w:space="0"/>'
    return '<w:sectPr><w:pgSz w:w="8400" w:h="6000"/><w:pgMar w:top="1000" w:right="720" w:bottom="1000" w:left="720" w:header="400" w:footer="400" w:gutter="0"/>%s</w:sectPr>' % c
HEIGHTS = [64, 66, 68, 70, 72, 74, 76, 78, 80, 82, 84]
FILL = 8   # one-line paragraphs above the picture
def variant(k, h):
    out = [para('T%d h=%d' % (k, h), ppr='<w:pageBreakBefore/>' if k else '')]
    for i in range(1, FILL + 1): out.append(para('T%d-f%d' % (k, i)))
    out.append(para('', SP15, inline(40, h)))
    out.append(para('', SP15))
    out.append(para('T%d-TAIL' % k))
    for i in range(1, 4): out.append(para('T%d-z%d' % (k, i)))
    return ''.join(out)
ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
drels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/p.png"/></Relationships>'
png = io.BytesIO(); Image.new('RGB', (80, 80), (200, 40, 40)).save(png, 'PNG')
for cols in (1, 2):
    _id[0] = 0
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W, ''.join(variant(k, h) for k, h in enumerate(HEIGHTS)), sect(cols))
    with zipfile.ZipFile('ef%d.docx' % cols, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', ct); z.writestr('_rels/.rels', rels); z.writestr('word/document.xml', doc)
        z.writestr('word/_rels/document.xml.rels', drels); z.writestr('word/media/p.png', png.getvalue())
