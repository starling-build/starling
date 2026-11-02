#!/usr/bin/env python3
"""Lab pie7 (Windows 01QbbApP, for amd-3): bestFit crowding of data labels on a 3-D pie (no manualLayout, no dLblPos).
Chart as pie5 'best': pie3DChart, rotX 30, varyColors, labels = name + percent, separator newline, inline frame 400.7 x 216 pt, A4 margins 72.
Sets: A = 25,11,9,6,6,5,5,4,4,3,3,3,2,14 (zh-27a874b7 chart 2); B = 40,30,12,8,4,3,2,1; C = 40,30,12,8,3,2,2,1,1,1; D = 35,25,12,8,3,3,3,3,2,2,2,2.
One doc pie9.docx, 32 pages, order: set (A B C D) x names (short long) x rotY (0 30) x perspective (30 0); page = index in combos().
gen.py OUT"""
import sys, os, zipfile
W_ = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"')
CNS = 'xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
L = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'


def spec(tag, vals, ry, long_idx=None):
    nm = [L[i] + L[i].lower() for i in range(len(vals))]
    if long_idx is not None:
        nm[long_idx] = 'Categ-Long'
    return (tag, vals, nm, ry)


def combos():
    c = [spec('ry%d' % r, [60, 36, 1, 1, 1, 1], r) for r in range(0, 37, 4)]
    c += [spec('long%d' % (i + 1), [60, 36, 1, 1, 1, 1], 0, i) for i in (2, 3, 4, 5)]
    c += [spec('t%d' % k, [60, 40 - 4 * k] + [k] * 4, 0) for k in (1, 2, 3)]
    for t, v, n, r in c:
        assert sum(v) == 100
    return c


def chart(t, sh, nm, ry):
    ps = 30
    cat = ''.join('<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, n) for i, n in enumerate(nm))
    val = ''.join('<c:pt idx="%d"><c:v>%d</c:v></c:pt>' % (i, v) for i, v in enumerate(sh))
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace %s><c:date1904 val="0"/><c:roundedCorners val="0"/><c:chart><c:autoTitleDeleted val="1"/>'
            '<c:view3D><c:rotX val="30"/><c:rotY val="%d"/><c:rAngAx val="0"/><c:perspective val="%d"/></c:view3D>'
            '<c:floor><c:thickness val="0"/></c:floor><c:sideWall><c:thickness val="0"/></c:sideWall><c:backWall><c:thickness val="0"/></c:backWall>'
            '<c:plotArea><c:layout/><c:pie3DChart><c:varyColors val="1"/><c:ser><c:idx val="0"/><c:order val="0"/>'
            '<c:dLbls><c:showLegendKey val="0"/><c:showVal val="0"/><c:showCatName val="1"/><c:showSerName val="0"/><c:showPercent val="1"/><c:showBubbleSize val="0"/><c:separator>\n</c:separator><c:showLeaderLines val="1"/></c:dLbls>'
            '<c:cat><c:strLit><c:ptCount val="%d"/>%s</c:strLit></c:cat><c:val><c:numLit><c:formatCode>General</c:formatCode><c:ptCount val="%d"/>%s</c:numLit></c:val></c:ser></c:pie3DChart></c:plotArea>'
            '<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>' % (CNS, ry, ps, len(sh), cat, len(sh), val))


def para(k, first):
    pb = '' if first else '<w:pageBreakBefore/>'
    return ('<w:p><w:pPr>%s<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="5088255" cy="2743200"/>'
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
    pkg(os.path.join(out, "pie9.docx"))
    print(len(combos()), "pages")
