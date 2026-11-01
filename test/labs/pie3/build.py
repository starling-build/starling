#!/usr/bin/env python3
"""Lab pie3: one 3-D pie, two slices (share s and the rest), only the first slice labelled with its unique category name.
usage: build.py OUTDIR   (12 documents, 24 charts each, 2 per page)"""
import sys, os, zipfile

SHARES = (8, 21, 45)                         # percent of the labelled slice
ROTYS = (0, 45, 90, 135, 180, 225, 270, 315)  # 3-D rotation about the vertical axis = where the slices start
ROTXS = (30, 15, 45)                         # elevation
POSS = ("bestFit", "inEnd", "outEnd", "ctr")
NS = ('xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')

def chart_xml(name, share, rotx, roty, pos):
    return (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace {NS}><c:date1904 val="0"/><c:roundedCorners val="0"/>'
            f'<c:chart><c:autoTitleDeleted val="1"/><c:view3D><c:rotX val="{rotx}"/><c:rotY val="{roty}"/><c:rAngAx val="0"/><c:perspective val="30"/></c:view3D>'
            '<c:floor><c:thickness val="0"/></c:floor><c:sideWall><c:thickness val="0"/></c:sideWall><c:backWall><c:thickness val="0"/></c:backWall>'
            '<c:plotArea><c:layout/><c:pie3DChart><c:varyColors val="1"/><c:ser><c:idx val="0"/><c:order val="0"/>'
            f'<c:dLbls><c:dLbl><c:idx val="1"/><c:delete val="1"/></c:dLbl><c:spPr><a:noFill/></c:spPr>'
            f'<c:dLblPos val="{pos}"/><c:showLegendKey val="0"/><c:showVal val="0"/><c:showCatName val="1"/><c:showSerName val="0"/><c:showPercent val="0"/><c:showBubbleSize val="0"/></c:dLbls>'
            f'<c:cat><c:strLit><c:ptCount val="2"/><c:pt idx="0"><c:v>{name}</c:v></c:pt><c:pt idx="1"><c:v>rest</c:v></c:pt></c:strLit></c:cat>'
            f'<c:val><c:numLit><c:formatCode>General</c:formatCode><c:ptCount val="2"/><c:pt idx="0"><c:v>{share}</c:v></c:pt><c:pt idx="1"><c:v>{100-share}</c:v></c:pt></c:numLit></c:val>'
            '</c:ser></c:pie3DChart></c:plotArea><c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>')

def inline(rid, n):
    return ('<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="5088255" cy="2743200"/><wp:effectExtent l="0" t="0" r="0" b="0"/>'
            f'<wp:docPr id="{n}" name="Chart {n}"/><wp:cNvGraphicFramePr/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
            '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
            f'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="{rid}"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>')

def build_doc(path, rotx, pos, code):
    charts = []  # (name, share, roty)
    for share in SHARES:
        for roty in ROTYS:
            charts.append((f"P{code}{share:02d}{roty:03d}", share, roty))
    body = ''
    parts = {}
    rels = ''
    for i, (name, share, roty) in enumerate(charts, 1):
        parts[f"word/charts/chart{i}.xml"] = chart_xml(name, share, rotx, roty, pos)
        rels += f'<Relationship Id="rId{i+10}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="charts/chart{i}.xml"/>'
        pb = '<w:pageBreakBefore/>' if i > 1 and i % 2 == 1 else ''
        body += (f'<w:p><w:pPr>{pb}<w:spacing w:after="0"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="18"/></w:rPr>'
                 f'<w:t>{name} share={share} rotX={rotx} rotY={roty} pos={pos}</w:t></w:r></w:p>')
        body += f'<w:p><w:pPr><w:spacing w:after="0"/></w:pPr>{inline(f"rId{i+10}", i)}</w:p>'
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="851" w:footer="992" w:gutter="0"/></w:sectPr>'
    document = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
                'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
                'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>' + body + sect + '</w:body></w:document>')
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          + ''.join(f'<Override PartName="/word/charts/chart{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>' for i in range(1, len(charts) + 1))
          + '</Types>')
    root = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
    drels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + rels + '</Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", ct); z.writestr("_rels/.rels", root)
        z.writestr("word/document.xml", document); z.writestr("word/_rels/document.xml.rels", drels)
        for k, v in parts.items(): z.writestr(k, v)

def main(out):
    os.makedirs(out, exist_ok=True)
    n = 0
    for rotx in ROTXS:
        for pos in POSS:
            n += 1
            name = f"pie3-{n:02d}-x{rotx}-{pos}.docx"
            build_doc(os.path.join(out, name), rotx, pos, f"{n:02d}")
            print(name)

if __name__ == "__main__":
    main(sys.argv[1])
