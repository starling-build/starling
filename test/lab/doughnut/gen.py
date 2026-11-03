#!/usr/bin/env python3
"""Lab doughnut (for windows: Excel for Windows prints): the ring of a doughnut chart against its frame.
tdf161607's doughnut is bigger in our print than in Excel's. One chart per sheet (page), anchored at A1 with
an exact size, four categories 20/1/1/12, slices filled, no title. One thing varied at a time from the base:
holeSize 50, 1 series, no data labels, legend right, 480 x 288 pt.
gen.py OUT.xlsx  -> a workbook of the sheets in combos(); print each sheet to PDF (one page a sheet, in order)."""
import sys, zipfile

CNS = ('xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
       'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')


def combos():
    base = dict(hole=50, series=1, labels=None, legend='r', w=480, h=288)
    out = [('base', {})]
    for hole in (10, 25, 75, 90):
        out.append(('hole%d' % hole, dict(hole=hole)))
    for n in (2, 3):
        out.append(('series%d' % n, dict(series=n)))
    out.append(('labels-val', dict(labels='val')))
    out.append(('labels-cat-pct', dict(labels='catpct')))
    for lg in (None, 'b', 't', 'l'):
        out.append(('legend-%s' % (lg or 'none'), dict(legend=lg)))
    for w, h in ((300, 200), (640, 384), (400, 400), (600, 200), (200, 400)):
        out.append(('size%dx%d' % (w, h), dict(w=w, h=h)))
    out.append(('hole75-labels-val-legend-none', dict(hole=75, labels='val', legend=None)))
    return [(n, {**base, **d}) for n, d in out]


def chart_xml(p):
    cats = ['Category 1', 'Category 2', 'Category 3', 'Category 4']
    vals = [[20, 1, 1, 12], [5, 8, 3, 9], [7, 2, 6, 4]]
    sers = ''
    for s in range(p['series']):
        col = 'BCD'[s]
        cat = '<c:cat><c:strRef><c:f>Sheet1!$A$2:$A$5</c:f><c:strCache><c:ptCount val="4"/>%s</c:strCache></c:strRef></c:cat>' % ''.join(
            '<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, v) for i, v in enumerate(cats))
        val = '<c:val><c:numRef><c:f>Sheet1!$%s$2:$%s$5</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val="4"/>%s</c:numCache></c:numRef></c:val>' % (
            col, col, ''.join('<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, v) for i, v in enumerate(vals[s])))
        dl = ''
        if p['labels']:
            cp = p['labels'] == 'catpct'
            dl = ('<c:dLbls><c:showLegendKey val="0"/><c:showVal val="%d"/><c:showCatName val="%d"/><c:showSerName val="0"/>'
                  '<c:showPercent val="%d"/><c:showBubbleSize val="0"/><c:showLeaderLines val="1"/></c:dLbls>') % (0 if cp else 1, 1 if cp else 0, 1 if cp else 0)
        sers += ('<c:ser><c:idx val="%d"/><c:order val="%d"/><c:tx><c:strRef><c:f>Sheet1!$%s$1</c:f><c:strCache><c:ptCount val="1"/>'
                 '<c:pt idx="0"><c:v>Series %d</c:v></c:pt></c:strCache></c:strRef></c:tx>%s%s%s</c:ser>') % (s, s, col, s + 1, dl, cat, val)
    legend = '<c:legend><c:legendPos val="%s"/><c:overlay val="0"/></c:legend>' % p['legend'] if p['legend'] else ''
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace %s><c:roundedCorners val="0"/><c:chart>'
            '<c:autoTitleDeleted val="1"/><c:plotArea><c:layout/><c:doughnutChart><c:varyColors val="1"/>%s'
            '<c:firstSliceAng val="0"/><c:holeSize val="%d"/></c:doughnutChart></c:plotArea>%s<c:plotVisOnly val="1"/>'
            '<c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>') % (CNS, sers, p['hole'], legend)


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
            '<c r="%s1" t="inlineStr"><is><t>Series %d</t></is></c>' % ('BCD'[s], s + 1) for s in range(p['series']))
        vals = [[20, 1, 1, 12], [5, 8, 3, 9], [7, 2, 6, 4]]
        for r in range(4):
            rows += '<row r="%d"><c r="A%d" t="inlineStr"><is><t>Category %d</t></is></c>%s</row>' % (
                r + 2, r + 2, r + 1, ''.join('<c r="%s%d"><v>%d</v></c>' % ('BCD'[s], r + 2, vals[s][r]) for s in range(p['series'])))
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
        z.writestr('xl/charts/chart%d.xml' % i, chart_xml(p))
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
