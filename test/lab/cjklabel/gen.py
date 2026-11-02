#!/usr/bin/env python3
"""Lab cjklabel (Windows 01QbbApP, for amd-3 / amd-1): CJK data-label face and line pitch in a Word chart.
One 2-D pie per page (inline 400.7 x 216 pt, A4 margins 72), labels = category name + value, separator newline, dLblPos outEnd.
Doc lang zh-TW (docDefaults eastAsia zh-TW), chart txPr defRPr: latin Calibri, a:ea typeface="" (as zh-b8de3ae2), lang zh-TW.
Pages: bold {0,1} x size {8, 9.96, 12} x text {latin, cjk}  = 12 charts.  Latin names: Aa/Bb..; CJK names: Chinese incl. digits in values.
gen.py OUT"""
import sys, os, zipfile
W_ = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"')
CNS = 'xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
VAL = [34, 21, 28, 17]
NAMES = {'latin': ['Alpha', 'Bravo', 'Cargo', 'Delta'],
         'cjk': ['捐贈及贈與收入', '日本', '會員費收入123', '其他收入']}


def chart(names, bold, sz):
    cat = ''.join('<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, n) for i, n in enumerate(names))
    val = ''.join('<c:pt idx="%d"><c:v>%d</c:v></c:pt>' % (i, v) for i, v in enumerate(VAL))
    tx = ('<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="%d" b="%d"><a:latin typeface="Calibri"/><a:ea typeface=""/></a:defRPr></a:pPr>'
          '<a:endParaRPr lang="zh-TW"/></a:p></c:txPr>' % (int(round(sz * 100)), bold))
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace %s><c:date1904 val="0"/><c:lang val="zh-TW"/><c:roundedCorners val="0"/><c:chart><c:autoTitleDeleted val="1"/>'
            '<c:plotArea><c:layout/><c:pieChart><c:varyColors val="1"/><c:ser><c:idx val="0"/><c:order val="0"/>'
            '<c:dLbls>%s<c:dLblPos val="outEnd"/><c:showLegendKey val="0"/><c:showVal val="1"/><c:showCatName val="1"/><c:showSerName val="0"/><c:showPercent val="0"/><c:showBubbleSize val="0"/><c:separator>\n</c:separator><c:showLeaderLines val="1"/></c:dLbls>'
            '<c:cat><c:strLit><c:ptCount val="4"/>%s</c:strLit></c:cat><c:val><c:numLit><c:formatCode>General</c:formatCode><c:ptCount val="4"/>%s</c:numLit></c:val></c:ser></c:pieChart></c:plotArea>'
            '<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>' % (CNS, tx, cat, val))


def para(k, first):
    pb = '' if first else '<w:pageBreakBefore/>'
    return ('<w:p><w:pPr>%s<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="5088255" cy="2743200"/>'
            '<wp:docPr id="%d" name="Chart %d"/><wp:cNvGraphicFramePr/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart r:id="rId%d"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>'
            % (pb, k + 1, k + 1, k + 10))


def pkg(path):
    combos = [(t, b, s) for b in (0, 1) for s in (8, 9.96, 12) for t in ('latin', 'cjk')]
    body = ''.join(para(k, k == 0) for k in range(len(combos)))
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W_, body, sect)
    sty = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles %s><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="MS Mincho" w:cs="Times New Roman"/>'
           '<w:sz w:val="21"/><w:szCs w:val="21"/><w:lang w:val="en-US" w:eastAsia="zh-TW" w:bidi="ar-SA"/></w:rPr></w:rPrDefault><w:pPrDefault/></w:docDefaults>'
           '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>' % W_)
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
          + ''.join('<Override PartName="/word/charts/chart%d.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>' % (k + 1) for k in range(len(combos))) + '</Types>')
    root = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    dr = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          + ''.join('<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="charts/chart%d.xml"/>' % (k + 10, k + 1) for k in range(len(combos))) + '</Relationships>')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        for n, v in (('[Content_Types].xml', ct), ('_rels/.rels', root), ('word/document.xml', doc), ('word/styles.xml', sty), ('word/_rels/document.xml.rels', dr)):
            z.writestr(n, v)
        for k, (t, b, s) in enumerate(combos):
            z.writestr('word/charts/chart%d.xml' % (k + 1), chart(NAMES[t], b, s))
    return combos


if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    c = pkg(os.path.join(out, 'cjkl.docx'))
    for k, x in enumerate(c):
        print('page', k + 1, x)
