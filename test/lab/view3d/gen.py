#!/usr/bin/env python3
"""Lab view3d (for windows: Excel for Windows prints): how a 3-D column / 3-D area chart's box follows c:view3D.
We drew chart-tdf111824 (3-D columns, standard grouping, rAngAx=1) and chart-test3DAreaChartZAxis (3-D area, rAngAx=0) from one
witness each; the box's height, depth and the perspective are guesses. One chart per sheet (page), anchored at A1 (row 8) with an exact size,
four categories, no title, legend at the foot, axes shown. One thing varied at a time from the base:
kind column, 2 series, standard grouping, depthPercent 100, hPercent absent (autoscale), gapDepth 150, rAngAx 1, 480 x 288 pt.
gen.py OUT.xlsx  -> a workbook of the sheets in combos(); print each sheet to PDF (one page a sheet, in order)."""
import sys, zipfile

CNS = ('xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
       'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')


def combos():
    base = dict(kind='col', series=2, w=480, h=288, depth=100, hp=None, gd=150, ra=1, persp=30, rotx=15, roty=20)
    out = []
    for kind in ('col', 'area'):
        k = kind
        out.append((k + '-base', dict(kind=k)))
        for n in (1, 4):
            out.append((k + '-series%d' % n, dict(kind=k, series=n)))
        for w, h in ((720, 360), (320, 400)):
            out.append((k + '-size%dx%d' % (w, h), dict(kind=k, w=w, h=h)))
        for d in (50, 200):
            out.append((k + '-depth%d' % d, dict(kind=k, depth=d)))
        for hp in (50, 100, 200):
            out.append((k + '-hp%d' % hp, dict(kind=k, hp=hp)))
        for g in (0, 300):
            out.append((k + '-gapd%d' % g, dict(kind=k, gd=g)))
        out.append((k + '-persp30', dict(kind=k, ra=0, persp=30)))
        out.append((k + '-persp60', dict(kind=k, ra=0, persp=60)))
        out.append((k + '-persp0', dict(kind=k, ra=0, persp=0)))
        out.append((k + '-persp30-hp100', dict(kind=k, ra=0, persp=30, hp=100)))
        out.append((k + '-persp30-s4', dict(kind=k, ra=0, persp=30, series=4)))
        out.append((k + '-rot30-40', dict(kind=k, rotx=30, roty=40)))
    return [(n, {**base, **d}) for n, d in out]


def chart_xml(p, sheet):
    cats = ['Category 1', 'Category 2', 'Category 3', 'Category 4']
    vals = [[4, 7, 3, 9], [5, 2, 6, 4], [8, 3, 5, 7], [2, 6, 7, 3]]
    sers = ''
    for s in range(p['series']):
        col = 'BCDE'[s]
        cat = '<c:cat><c:strRef><c:f>@@S@@!$A$2:$A$5</c:f><c:strCache><c:ptCount val="4"/>%s</c:strCache></c:strRef></c:cat>' % ''.join(
            '<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, v) for i, v in enumerate(cats))
        val = '<c:val><c:numRef><c:f>@@S@@!$%s$2:$%s$5</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val="4"/>%s</c:numCache></c:numRef></c:val>' % (
            col, col, ''.join('<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, v) for i, v in enumerate(vals[s])))
        inv = '<c:invertIfNegative val="0"/>' if p['kind'] == 'col' else ''
        sers += ('<c:ser><c:idx val="%d"/><c:order val="%d"/><c:tx><c:strRef><c:f>@@S@@!$%s$1</c:f><c:strCache><c:ptCount val="1"/>'
                 '<c:pt idx="0"><c:v>Series %d</c:v></c:pt></c:strCache></c:strRef></c:tx>%s%s%s</c:ser>') % (s, s, col, s + 1, inv, cat, val)
    view = '<c:view3D><c:rotX val="%d"/>%s<c:rotY val="%d"/><c:depthPercent val="%d"/><c:rAngAx val="%d"/>%s</c:view3D>' % (
        p['rotx'], '<c:hPercent val="%d"/>' % p['hp'] if p['hp'] else '', p['roty'], p['depth'], p['ra'], '' if p['ra'] else '<c:perspective val="%d"/>' % p['persp'])
    if p['kind'] == 'col':
        plot = ('<c:bar3DChart><c:barDir val="col"/><c:grouping val="standard"/><c:varyColors val="0"/>%s<c:gapWidth val="150"/><c:gapDepth val="%d"/>'
                '<c:shape val="box"/><c:axId val="111"/><c:axId val="222"/><c:axId val="333"/></c:bar3DChart>') % (sers, p['gd'])
    else:
        plot = ('<c:area3DChart><c:grouping val="standard"/><c:varyColors val="0"/>%s<c:gapDepth val="%d"/>'
                '<c:axId val="111"/><c:axId val="222"/><c:axId val="333"/></c:area3DChart>') % (sers, p['gd'])
    axes = ('<c:catAx><c:axId val="111"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="b"/>'
            '<c:numFmt formatCode="General" sourceLinked="1"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/>'
            '<c:crossAx val="222"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx>'
            '<c:valAx><c:axId val="222"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="l"/>'
            '<c:majorGridlines/><c:numFmt formatCode="General" sourceLinked="1"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/>'
            '<c:crossAx val="111"/><c:crosses val="autoZero"/><c:crossBetween val="%s"/></c:valAx>') % ('between' if p['kind'] == 'col' else 'midCat')
    if p['series'] > 1:
        axes += ('<c:serAx><c:axId val="333"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="b"/>'
                 '<c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/><c:crossAx val="222"/><c:crosses val="autoZero"/></c:serAx>')
    else:
        plot = plot.replace('<c:axId val="333"/>', '')
    xml = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace %s><c:roundedCorners val="0"/><c:chart>'
           '<c:autoTitleDeleted val="1"/>%s<c:plotArea><c:layout/>%s%s</c:plotArea><c:legend><c:legendPos val="b"/><c:overlay val="0"/></c:legend>'
           '<c:plotVisOnly val="1"/><c:dispBlanksAs val="zero"/></c:chart></c:chartSpace>') % (CNS, view, plot, axes)
    return xml.replace('@@S@@', "'%s'" % sheet)

def main(out):
    cs = combos()
    ct = ['<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
          '<Default Extension="xml" ContentType="application/xml"/>',
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>']
    wbsheets, wbrels = '', ''
    z = zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED)
    for i, (name, p) in enumerate(cs, 1):
        ct.append('<Override PartName="/xl/worksheets/sheet%d.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' % i)
        ct.append('<Override PartName="/xl/drawings/drawing%d.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>' % i)
        ct.append('<Override PartName="/xl/charts/chart%d.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>' % i)
        wbsheets += '<sheet name="%s" sheetId="%d" r:id="rId%d"/>' % (name[:31], i, i)
        wbrels += '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet%d.xml"/>' % (i, i)
        rows = '<row r="1"><c r="A1" t="inlineStr"><is><t>x</t></is></c>%s</row>' % ''.join(
            '<c r="%s1" t="inlineStr"><is><t>Series %d</t></is></c>' % ('BCDE'[s], s + 1) for s in range(p['series']))
        vals = [[4, 7, 3, 9], [5, 2, 6, 4], [8, 3, 5, 7], [2, 6, 7, 3]]
        for r in range(4):
            rows += '<row r="%d"><c r="A%d" t="inlineStr"><is><t>Category %d</t></is></c>%s</row>' % (
                r + 2, r + 2, r + 1, ''.join('<c r="%s%d"><v>%d</v></c>' % ('BCDE'[s], r + 2, vals[s][r]) for s in range(p['series'])))
        z.writestr('xl/worksheets/sheet%d.xml' % i,
                   '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                   'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheetData>%s</sheetData>'
                   '<pageMargins left="0.5" right="0.5" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>'
                   '<pageSetup orientation="landscape"/><drawing r:id="rId1"/></worksheet>' % rows)
        z.writestr('xl/worksheets/_rels/sheet%d.xml.rels' % i,
                   '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing%d.xml"/></Relationships>' % i)
        emu = 12700
        z.writestr('xl/drawings/drawing%d.xml' % i,
                   '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
                   'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><xdr:oneCellAnchor><xdr:from><xdr:col>0</xdr:col><xdr:colOff>0</xdr:colOff>'
                   '<xdr:row>7</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:ext cx="%d" cy="%d"/><xdr:graphicFrame macro=""><xdr:nvGraphicFramePr>'
                   '<xdr:cNvPr id="2" name="Chart 1"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr><xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm>'
                   '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
                   'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="rId1"/></a:graphicData></a:graphic></xdr:graphicFrame>'
                   '<xdr:clientData/></xdr:oneCellAnchor></xdr:wsDr>' % (p['w'] * emu, p['h'] * emu))
        z.writestr('xl/drawings/_rels/drawing%d.xml.rels' % i,
                   '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart%d.xml"/></Relationships>' % i)
        z.writestr('xl/charts/chart%d.xml' % i, chart_xml(p, name[:31]))
    z.writestr('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">%s</Types>' % ''.join(ct))
    z.writestr('_rels/.rels', '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
               '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
    z.writestr('xl/workbook.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
               'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>%s</sheets></workbook>' % wbsheets)
    z.writestr('xl/_rels/workbook.xml.rels', '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">%s</Relationships>' % wbrels)
    z.close()
    for i, (n, p) in enumerate(cs, 1):
        print(i, n, p)


if __name__ == '__main__':
    main(sys.argv[1])
