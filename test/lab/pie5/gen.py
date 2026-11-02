#!/usr/bin/env python3
"""Lab pie5 (Windows 01QbbApP, for amd-3): Word's 3-D pie data labels, inside vs outside.
One 3-D pie per page (inline chart frame 400.7 x 216 pt at the margin, A4, margins 72): rotX 30, persp 30, rAngAx 0, varyColors,
labels = category name + percentage (no value), separator newline; shares 2,3,5,8,12,20,50 (%).
Charts per doc: names short (2 chars) / long (8 chars)  x  rotY 0,90,180,270 (3-D pies have no c:firstSliceAng; Excel stores
the 'angle of first slice' of a 3-D pie in view3D rotY)  = 8 pages.  Docs: pie5-best (no dLblPos), pie5-inEnd, pie5-outEnd, pie5-ctr.
gen.py OUT"""
import sys, os, zipfile
W_ = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"')
SH = [2, 3, 5, 8, 12, 20, 50]
SHORT = ["Aa", "Bb", "Cc", "Dd", "Ee", "Ff", "Gg"]
LONG = ["Categ-A1", "Categ-B2", "Categ-C3", "Categ-D4", "Categ-E5", "Categ-F6", "Categ-G7"]
CNS = 'xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'


def chart(names, roty, pos):
    cat = ''.join('<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, n) for i, n in enumerate(names))
    val = ''.join('<c:pt idx="%d"><c:v>%d</c:v></c:pt>' % (i, v) for i, v in enumerate(SH))
    dp = '<c:dLblPos val="%s"/>' % pos if pos else ''
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace %s><c:date1904 val="0"/><c:roundedCorners val="0"/><c:chart><c:autoTitleDeleted val="1"/>'
            '<c:view3D><c:rotX val="30"/><c:rotY val="%d"/><c:rAngAx val="0"/><c:perspective val="30"/></c:view3D>'
            '<c:floor><c:thickness val="0"/></c:floor><c:sideWall><c:thickness val="0"/></c:sideWall><c:backWall><c:thickness val="0"/></c:backWall>'
            '<c:plotArea><c:layout/><c:pie3DChart><c:varyColors val="1"/><c:ser><c:idx val="0"/><c:order val="0"/>'
            '<c:dLbls>%s<c:showLegendKey val="0"/><c:showVal val="0"/><c:showCatName val="1"/><c:showSerName val="0"/><c:showPercent val="1"/><c:showBubbleSize val="0"/><c:separator>\n</c:separator><c:showLeaderLines val="1"/></c:dLbls>'
            '<c:cat><c:strLit><c:ptCount val="7"/>%s</c:strLit></c:cat><c:val><c:numLit><c:formatCode>General</c:formatCode><c:ptCount val="7"/>%s</c:numLit></c:val></c:ser></c:pie3DChart></c:plotArea>'
            '<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>' % (CNS, roty, dp, cat, val))


def para(k, first):
    pb = '' if first else '<w:pageBreakBefore/>'
    return ('<w:p><w:pPr>%s<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="5088255" cy="2743200"/>'
            '<wp:docPr id="%d" name="Chart %d"/><wp:cNvGraphicFramePr/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart r:id="rId%d"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>'
            % (pb, k + 1, k + 1, k + 10))


def pkg(path, pos):
    combos = [(n, a) for n in (SHORT, LONG) for a in (0, 90, 180, 270)]
    body = ''.join(para(k, k == 0) for k in range(len(combos)))
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W_, body, sect)
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          + ''.join('<Override PartName="/word/charts/chart%d.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>' % (k + 1) for k in range(len(combos))) + '</Types>')
    root = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    dr = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          + ''.join('<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="charts/chart%d.xml"/>' % (k + 10, k + 1) for k in range(len(combos))) + '</Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, v in (("[Content_Types].xml", ct), ("_rels/.rels", root), ("word/document.xml", doc), ("word/_rels/document.xml.rels", dr)):
            z.writestr(n, v)
        for k, (names, a) in enumerate(combos):
            z.writestr("word/charts/chart%d.xml" % (k + 1), chart(names, a, pos))


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for nm, pos in (("best", None), ("inEnd", "inEnd"), ("outEnd", "outEnd"), ("ctr", "ctr")):
        pkg(os.path.join(out, "pie5-%s.docx" % nm), pos)
        print(nm)
