#!/usr/bin/env python3
"""build.py -> anc.docx: pictures anchored in a two-column section that a continuous one-column section follows (amd-3, for lo-eb12e7d4 p15). Needs PIL (a 40x40 png)."""
import zipfile, sys, io
from PIL import Image
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
EMU = 12700
SP = '<w:spacing w:after="0" w:line="240" w:lineRule="auto"/>'
def run(t): return '<w:r><w:t xml:space="preserve">%s</w:t></w:r>' % t
def para(t, extra='', ppr=''): return '<w:p><w:pPr>%s%s</w:pPr>%s%s</w:p>' % (SP, ppr, run(t), extra)
_id = [0]
def graphic(w, h):
    _id[0] += 1
    return ('<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="%d" name="p%d"/><pic:cNvPicPr/></pic:nvPicPr>'
            '<pic:blipFill><a:blip r:embed="rId2"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="%d" cy="%d"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic>') % (_id[0], _id[0], w * EMU, h * EMU)
def inline(w, h):
    _id[0] += 1
    return '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="%d" cy="%d"/><wp:docPr id="%d" name="i%d"/>%s</wp:inline></w:drawing></w:r>' % (w * EMU, h * EMU, _id[0] + 100, _id[0], graphic(w, h))
def anchor(w, h, x, y, wrap, relH='column', relV='paragraph'):
    _id[0] += 1
    wr = {'none': '<wp:wrapNone/>', 'tb': '<wp:wrapTopAndBottom/>', 'sq': '<wp:wrapSquare wrapText="bothSides"/>'}[wrap]
    return ('<w:r><w:drawing><wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="1" behindDoc="0" locked="0" layoutInCell="1" allowOverlap="1">'
            '<wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="%s"><wp:posOffset>%d</wp:posOffset></wp:positionH><wp:positionV relativeFrom="%s"><wp:posOffset>%d</wp:posOffset></wp:positionV>'
            '<wp:extent cx="%d" cy="%d"/><wp:effectExtent l="0" t="0" r="0" b="0"/>%s<wp:docPr id="%d" name="a%d"/><wp:cNvGraphicFramePr/>%s</wp:anchor></w:drawing></w:r>'
            ) % (relH, x * EMU, relV, y * EMU, w * EMU, h * EMU, wr, _id[0] + 100, _id[0], graphic(w, h))
def sect(cols, typ):
    c = '<w:cols w:num="2" w:space="40"/>' if cols == 2 else '<w:cols w:space="0"/>'
    return '<w:sectPr><w:type w:val="%s"/><w:pgSz w:w="8400" w:h="6000"/><w:pgMar w:top="1000" w:right="720" w:bottom="1000" w:left="720" w:header="400" w:footer="400" w:gutter="0"/>%s</w:sectPr>' % (typ, c)
def variant(tag, n, pic):
    """n one-line paragraphs in two columns; pic = (paragraph index 1-based, kind, args) or None."""
    out = ['<w:p><w:pPr>%s%s</w:pPr>%s</w:p>' % (SP, sect(1, 'nextPage'), run(tag))]
    for i in range(1, n + 1):
        extra = ''
        if pic and pic[0] == i:
            kind, args = pic[1], pic[2]
            extra = inline(*args) if kind == 'inline' else anchor(*args[:4], kind)
        ppr = sect(2, 'continuous') if i == n else ''
        out.append(para('%s-p%d' % (tag, i), extra, ppr))
    out.append('<w:p><w:pPr>%s%s</w:pPr>%s</w:p>' % (SP, sect(1, 'continuous'), run(tag + '-after')))
    return ''.join(out)
# tag, paragraphs, (anchor paragraph, kind, (w, h, x, y)) ; x from the column's left, y from the paragraph's top (pt)
CASES = [
    ('A', 12, None),                                  # control: 12 lines in two columns of 6
    ('B', 12, (3, 'none', (40, 40, 20, 0))),          # a picture with no wrap in line 3's paragraph
    ('C', 12, (3, 'tb', (40, 40, 20, 0))),            # top-and-bottom: 40pt kept clear
    ('D', 12, (3, 'sq', (40, 40, 20, 0))),            # square wrap
    ('E', 12, (3, 'inline', (40, 40))),               # inline: the line is 40pt high
    ('F', 12, (12, 'none', (40, 40, 20, 0))),         # no wrap, in the LAST paragraph (the right column)
    ('G', 12, (3, 'none', (40, 100, 20, 0))),         # no wrap, 100pt high: reaches under the text of the left column
    ('H', 12, (3, 'none', (40, 40, 100, 0))),         # no wrap, x = 100: straddles the column gap (columns are 150pt wide)
    ('I', 12, (3, 'none', (40, 40, 20, 150))),        # no wrap, 150pt below the line: below the balanced block
    ('J', 12, (3, 'tb', (40, 100, 20, 0))),           # top-and-bottom, 100pt
]
body = ''.join(variant(*c) for c in CASES)
doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W, body, sect(1, 'continuous'))
ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
drels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/p.png"/></Relationships>'
png = io.BytesIO(); Image.new('RGB', (80, 80), (200, 40, 40)).save(png, 'PNG')
out = sys.argv[1] if len(sys.argv) > 1 else 'anc.docx'
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', ct); z.writestr('_rels/.rels', rels); z.writestr('word/document.xml', doc)
    z.writestr('word/_rels/document.xml.rels', drels); z.writestr('word/media/p.png', png.getvalue())
