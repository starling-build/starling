#!/usr/bin/env python3
"""Lab proj (for amd-opus): how Word projects a 3-D chart's box. Each page holds one 3-D column chart
(bar3DChart, barDir col, grouping standard: a true series axis) whose floor, back wall and side wall
are drawn as plain 1pt black outlines with no fill and no gridlines, so the projected box's corners can
be read from the PDF's vector paths exactly. 3 categories x 2 series, values 1..6, axes deleted, no title,
no legend, no labels. Frame 400 x 300 pt inline, A4, margins 72.
Varied: rotX, rotY, perspective, rAngAx, depthPercent, hPercent, and auto vs a manual inner plot layout.
gen.py OUTDIR  -> OUTDIR/proj.docx, one chart a page; page = index in combos() + 1."""
import sys, os, zipfile
W_ = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"')
CNS = 'xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
LN = '<c:spPr><a:noFill/><a:ln w="12700"><a:solidFill><a:srgbClr val="000000"/></a:solidFill></a:ln></c:spPr>'
NOLN = '<c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr>'


def combos():
    out = []
    # (rotX, rotY, persp, rAngAx, depth, hPct, manual)
    for rx in (0, 15, 30, 45, 60):
        for ry in (0, 20, 45, 90, 160, 300):
            out.append((rx, ry, 30, 0, 100, None, False))
    for ps in (0, 15, 60, 100, 200):
        for ry in (20, 45):
            out.append((30, ry, ps, 0, 100, None, False))
    for ry in (0, 20, 45, 90):
        out.append((15, ry, 30, 1, 100, None, False))
        out.append((40, ry, 30, 1, 100, None, False))
    for dp in (50, 200, 500):
        out.append((15, 20, 30, 0, dp, None, False))
        out.append((15, 20, 30, 1, dp, None, False))
    for hp in (50, 200):
        out.append((15, 20, 30, 0, 100, hp, False))
        out.append((15, 20, 30, 1, 100, hp, False))
    for c in [(15, 20, 30, 0, 100, None, True), (30, 45, 30, 0, 100, None, True), (15, 20, 30, 1, 100, None, True)]:
        out.append(c)
    return out


def chart(rx, ry, ps, ra, dp, hp, manual):
    ser = ''
    for s in range(2):
        val = ''.join('<c:pt idx="%d"><c:v>%d</c:v></c:pt>' % (i, 1 + s * 3 + i) for i in range(3))
        cat = ''.join('<c:pt idx="%d"><c:v>C%d</c:v></c:pt>' % (i, i + 1) for i in range(3))
        ser += ('<c:ser><c:idx val="%d"/><c:order val="%d"/><c:tx><c:v>S%d</c:v></c:tx>'
                '<c:spPr><a:solidFill><a:srgbClr val="%s"/></a:solidFill></c:spPr><c:invertIfNegative val="0"/>'
                '<c:cat><c:strLit><c:ptCount val="3"/>%s</c:strLit></c:cat><c:val><c:numLit><c:formatCode>General</c:formatCode><c:ptCount val="3"/>%s</c:numLit></c:val></c:ser>'
                % (s, s, s + 1, ('4472C4', 'ED7D31')[s], cat, val))
    layout = ('<c:layout><c:manualLayout><c:layoutTarget val="inner"/><c:xMode val="edge"/><c:yMode val="edge"/>'
              '<c:x val="0.1"/><c:y val="0.1"/><c:w val="0.8"/><c:h val="0.8"/></c:manualLayout></c:layout>') if manual else '<c:layout/>'
    v3 = '<c:view3D><c:rotX val="%d"/>%s<c:rotY val="%d"/>%s<c:rAngAx val="%d"/><c:perspective val="%d"/></c:view3D>' % (
        rx, '<c:hPercent val="%d"/>' % hp if hp else '', ry, '<c:depthPercent val="%d"/>' % dp, ra, ps)
    ax = lambda tag, i, cross, extra: ('<c:%s><c:axId val="%d"/><c:scaling><c:orientation val="minMax"/>%s</c:scaling><c:delete val="1"/>'
                                       '<c:axPos val="b"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="none"/>'
                                       '<c:crossAx val="%d"/></c:%s>' % (tag, i, extra, cross, tag))
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace %s><c:date1904 val="0"/><c:roundedCorners val="0"/><c:chart>'
            '<c:autoTitleDeleted val="1"/>%s<c:floor><c:thickness val="0"/>%s</c:floor><c:sideWall><c:thickness val="0"/>%s</c:sideWall>'
            '<c:backWall><c:thickness val="0"/>%s</c:backWall><c:plotArea>%s<c:bar3DChart><c:barDir val="col"/><c:grouping val="standard"/>'
            '<c:varyColors val="0"/>%s<c:gapWidth val="150"/><c:shape val="box"/><c:axId val="1"/><c:axId val="2"/><c:axId val="3"/></c:bar3DChart>'
            '%s%s%s%s</c:plotArea><c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart>'
            '<c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr></c:chartSpace>'
            % (CNS, v3, LN, LN, LN, layout, ser,
               ax('catAx', 1, 2, ''), ax('valAx', 2, 1, '<c:max val="6"/><c:min val="0"/>').replace('<c:delete val="1"/>', '<c:delete val="1"/>'),
               ax('serAx', 3, 2, ''), NOLN))


def para(k, first):
    pb = '' if first else '<w:pageBreakBefore/>'
    return ('<w:p><w:pPr>%s<w:spacing w:before="0" w:after="0"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="5080000" cy="3810000"/>'
            '<wp:docPr id="%d" name="Chart %d"/><wp:cNvGraphicFramePr/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart r:id="rId%d"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>'
            % (pb, k + 1, k + 1, k + 10))


def pkg(path):
    cb = combos()
    body = ''.join(para(k, k == 0) for k in range(len(cb)))
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W_, body, sect)
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          + ''.join('<Override PartName="/word/charts/chart%d.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>' % (k + 1) for k in range(len(cb))) + '</Types>')
    root = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    dr = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          + ''.join('<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="charts/chart%d.xml"/>' % (k + 10, k + 1) for k in range(len(cb))) + '</Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, v in (("[Content_Types].xml", ct), ("_rels/.rels", root), ("word/document.xml", doc), ("word/_rels/document.xml.rels", dr)):
            z.writestr(n, v)
        for k, c in enumerate(cb):
            z.writestr("word/charts/chart%d.xml" % (k + 1), chart(*c))


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    pkg(os.path.join(out, "proj.docx"))
    print(len(combos()), "pages")
