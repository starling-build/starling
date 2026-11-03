#!/usr/bin/env python3
"""Lab pie10 (for amd-opus): the 3-D pie's CROWD WALK. zh-27a874b7's chart's view (rotX 30, rotY 0, perspective 30),
labels name + percent on two lines (as lab pie7), inline frame 400.7 x 216pt. A group of 2% slices walks round the pie
behind a leading slice L% that grows by 4: the group's labels against the lone slice's at the same place show which way
Word pushes crowded labels apart, and by how much, everywhere round the rim.
Sets (one page each, in this order): S = [L, 2, 98-L] (one small slice), P = [L, 2, 2, 96-L] (two), T = [L, 2, 2, 2, 94-L]
(three), Q = [L, 2, 2, 2, 2, 92-L] (four); L = 2, 6, 10, ... while the last slice keeps 2% or more.
gen.py OUTDIR -> OUTDIR/pie10.docx; meas.py PDF > PIE10-WORD.tsv (lab pie7's reader)."""
import sys, os, zipfile
W_ = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"')
CNS = 'xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
SETS = {}
for kind, n in (('S', 1), ('P', 2), ('T', 3), ('Q', 4)):
    lead = 2
    while 100 - lead - 2 * n >= 2:
        SETS['%s%02d' % (kind, lead)] = [lead] + [2] * n + [100 - lead - 2 * n]
        lead += 4
for k, v in SETS.items():
    assert sum(v) == 100, k
def names(kind, n):
    L = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    return [(L[i] + L[i].lower()) if kind == 'short' else 'Categ-%s%d' % (L[i], i + 1) for i in range(n)]


def combos():
    return [(s, 'short', 0, 30) for s in SETS]
def chart(s, nk, ry, ps):
    sh = SETS[s]; nm = names(nk, len(sh))
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
    pkg(os.path.join(out, "pie10.docx"))
    print(len(combos()), "pages")
