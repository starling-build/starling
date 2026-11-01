#!/usr/bin/env python3
"""Lab ch3 (Windows 01QbbApP, for amd-5): one 3-D clustered column chart per page, right-angle axes, 8 variants. usage: build.py OUTDIR -> ch3.docx"""
import sys, os, zipfile
NS = ('xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')
# (name, top label, rotX, rotY, valTitle, catTitle)   top label sets the value axis: max = top, major = top/3
VARS = [("V01-lab9-x15-y20", 9, 15, 20, 0, 0), ("V02-lab999-x15-y20", 999, 15, 20, 0, 0), ("V03-lab99999-x15-y20", 99999, 15, 20, 0, 0),
        ("V04-lab999-x30-y20", 999, 30, 20, 0, 0), ("V05-lab999-x15-y40", 999, 15, 40, 0, 0),
        ("V06-lab999-x15-y20-valTitle", 999, 15, 20, 1, 0), ("V07-lab999-x15-y20-catTitle", 999, 15, 20, 0, 1), ("V08-lab999-x15-y20-bothTitles", 999, 15, 20, 1, 1)]
CATS = ["C1", "C2", "C3", "C4", "C5", "C6"]


def title(text, rot):
    return (f'<c:title><c:tx><c:rich><a:bodyPr rot="{rot}" vert="horz"/><a:p><a:pPr><a:defRPr sz="1000" b="0"/></a:pPr><a:r><a:rPr lang="zh-CN" sz="1000" b="0"/><a:t>{text}</a:t></a:r></a:p></c:rich></c:tx><c:overlay val="0"/></c:title>')


def chart_xml(top, rx, ry, vt, ct):
    def ser(i, nm, k):
        vals = [round(top * f) for f in ([.5, .8, .3, 1.0, .6, .4] if k == 0 else [.7, .4, .9, .2, .8, .55])]
        return (f'<c:ser><c:idx val="{i}"/><c:order val="{i}"/><c:tx><c:strRef><c:f>Sheet1!$B$1</c:f><c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>{nm}</c:v></c:pt></c:strCache></c:strRef></c:tx>'
                '<c:invertIfNegative val="0"/><c:cat><c:strLit><c:ptCount val="6"/>' + ''.join(f'<c:pt idx="{j}"><c:v>{c}</c:v></c:pt>' for j, c in enumerate(CATS)) + '</c:strLit></c:cat>'
                '<c:val><c:numLit><c:formatCode>#,##0</c:formatCode><c:ptCount val="6"/>' + ''.join(f'<c:pt idx="{j}"><c:v>{v}</c:v></c:pt>' for j, v in enumerate(vals)) + '</c:numLit></c:val></c:ser>')
    return (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace {NS}><c:date1904 val="0"/><c:roundedCorners val="0"/>'
            f'<c:chart><c:autoTitleDeleted val="1"/><c:view3D><c:rotX val="{rx}"/><c:rotY val="{ry}"/><c:depthPercent val="100"/><c:rAngAx val="1"/></c:view3D>'
            '<c:floor><c:thickness val="0"/></c:floor><c:sideWall><c:thickness val="0"/></c:sideWall><c:backWall><c:thickness val="0"/></c:backWall>'
            '<c:plotArea><c:layout/><c:bar3DChart><c:barDir val="col"/><c:grouping val="clustered"/><c:varyColors val="0"/>' + ser(0, "S1", 0) + ser(1, "S2", 1) +
            '<c:gapWidth val="150"/><c:shape val="box"/><c:axId val="111"/><c:axId val="222"/><c:axId val="0"/></c:bar3DChart>'
            '<c:catAx><c:axId val="111"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="b"/>' + (title("类别", 0) if ct else '') +
            '<c:numFmt formatCode="General" sourceLinked="0"/><c:majorTickMark val="out"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/><c:crossAx val="222"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx>'
            f'<c:valAx><c:axId val="222"/><c:scaling><c:orientation val="minMax"/><c:max val="{top}"/><c:min val="0"/></c:scaling><c:delete val="0"/><c:axPos val="l"/><c:majorGridlines/>' + (title("千元", -5400000) if vt else '') +
            '<c:numFmt formatCode="#,##0" sourceLinked="0"/><c:majorTickMark val="out"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/><c:crossAx val="111"/><c:crosses val="autoZero"/><c:crossBetween val="between"/>'
            f'<c:majorUnit val="{top/3:g}"/></c:valAx></c:plotArea><c:legend><c:legendPos val="b"/><c:overlay val="0"/></c:legend><c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>')


def inline(rid, n):
    return ('<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="6096000" cy="3556000"/><wp:effectExtent l="0" t="0" r="0" b="0"/>'
            f'<wp:docPr id="{n}" name="Chart {n}"/><wp:cNvGraphicFramePr/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
            '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
            f'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="{rid}"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>')


def main(out):
    os.makedirs(out, exist_ok=True)
    body = ''
    parts = {}
    rels = ''
    for i, (nm, top, rx, ry, vt, ct) in enumerate(VARS, 1):
        parts[f"word/charts/chart{i}.xml"] = chart_xml(top, rx, ry, vt, ct)
        rels += f'<Relationship Id="rId{i+10}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="charts/chart{i}.xml"/>'
        pb = '<w:pageBreakBefore/>' if i > 1 else ''
        body += (f'<w:p><w:pPr>{pb}<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="exact"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="16"/></w:rPr><w:t>{nm}</w:t></w:r></w:p>')
        body += f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>{inline(f"rId{i+10}", i)}</w:p>'
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720" w:header="360" w:footer="360" w:gutter="0"/></w:sectPr>'
    document = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
                'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
                'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>' + body + sect + '</w:body></w:document>')
    ct_ = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
           '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
           '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
           + ''.join(f'<Override PartName="/word/charts/chart{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>' for i in range(1, len(VARS) + 1)) + '</Types>')
    root = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
    drels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + rels + '</Relationships>')
    with zipfile.ZipFile(os.path.join(out, "ch3.docx"), "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", ct_)
        z.writestr("_rels/.rels", root)
        z.writestr("word/document.xml", document)
        z.writestr("word/_rels/document.xml.rels", drels)
        for k, v in parts.items():
            z.writestr(k, v)


if __name__ == "__main__":
    main(sys.argv[1])
