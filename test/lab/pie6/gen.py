#!/usr/bin/env python3
"""Lab pie6 (Windows 01QbbApP, for amd-3): ONE moved data label (c:dLbl/c:layout/c:manualLayout x,y) on a 3-D pie.
Chart as pie5 'best': pie3DChart, rotX 30, rotY 0, perspective 30, rAngAx 0, varyColors, no dLblPos, inline frame 400.7 x 216 pt, A4 margins 72.
Shares 2,3,5,8,12,20,50 (%), names Aa..Gg.  Moved slice: idx 5 (20%, 'Ff', inside by default) or idx 2 (5%, 'Cc', outside by default).
Label formats: f1 = name + percent, separator ' ' ; f2 = name + percent, separator newline ; f3 = name + value + percent, separator newline.
Offsets (x,y): none (baseline), (0.1,0) (-0.1,0) (0,0.1) (0,-0.1) (0.15,0.15).  One doc pie6.docx, 36 pages in the order
slice (5, 2) x format (f1, f2, f3) x offset (6)  (page = ((s*3)+f)*6 + o + 1).
gen.py OUT"""
import sys, os, zipfile
W_ = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"')
SH = [2, 3, 5, 8, 12, 20, 50]
NAMES = ["Aa", "Bb", "Cc", "Dd", "Ee", "Ff", "Gg"]
CNS = 'xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
SLICES = [5, 2]
FMT = {'f1': (0, ' '), 'f2': (0, '\n'), 'f3': (1, '\n')}   # showVal, separator
OFFS = [None, (0.1, 0), (-0.1, 0), (0, 0.1), (0, -0.1), (0.15, 0.15)]


def chart(sl, fmt, off):
    sv, sep = FMT[fmt]
    cat = ''.join('<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, n) for i, n in enumerate(NAMES))
    val = ''.join('<c:pt idx="%d"><c:v>%d</c:v></c:pt>' % (i, v) for i, v in enumerate(SH))
    flags = ('<c:showLegendKey val="0"/><c:showVal val="%d"/><c:showCatName val="1"/><c:showSerName val="0"/><c:showPercent val="1"/><c:showBubbleSize val="0"/><c:separator>%s</c:separator>' % (sv, sep))
    one = ''
    if off:
        one = ('<c:dLbl><c:idx val="%d"/><c:layout><c:manualLayout><c:x val="%s"/><c:y val="%s"/></c:manualLayout></c:layout>%s</c:dLbl>' % (sl, off[0], off[1], flags))
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace %s><c:date1904 val="0"/><c:roundedCorners val="0"/><c:chart><c:autoTitleDeleted val="1"/>'
            '<c:view3D><c:rotX val="30"/><c:rotY val="0"/><c:rAngAx val="0"/><c:perspective val="30"/></c:view3D>'
            '<c:floor><c:thickness val="0"/></c:floor><c:sideWall><c:thickness val="0"/></c:sideWall><c:backWall><c:thickness val="0"/></c:backWall>'
            '<c:plotArea><c:layout/><c:pie3DChart><c:varyColors val="1"/><c:ser><c:idx val="0"/><c:order val="0"/>'
            '<c:dLbls>%s%s<c:showLeaderLines val="1"/></c:dLbls>'
            '<c:cat><c:strLit><c:ptCount val="7"/>%s</c:strLit></c:cat><c:val><c:numLit><c:formatCode>General</c:formatCode><c:ptCount val="7"/>%s</c:numLit></c:val></c:ser></c:pie3DChart></c:plotArea>'
            '<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>' % (CNS, one, flags, cat, val))


def para(k, first):
    pb = '' if first else '<w:pageBreakBefore/>'
    return ('<w:p><w:pPr>%s<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="5088255" cy="2743200"/>'
            '<wp:docPr id="%d" name="Chart %d"/><wp:cNvGraphicFramePr/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart r:id="rId%d"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>'
            % (pb, k + 1, k + 1, k + 10))


def combos():
    return [(s, f, o) for s in SLICES for f in FMT for o in OFFS]


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
        for k, (s, f, o) in enumerate(cb):
            z.writestr("word/charts/chart%d.xml" % (k + 1), chart(s, f, o))


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    pkg(os.path.join(out, "pie6.docx"))
    print(len(combos()), "pages")
