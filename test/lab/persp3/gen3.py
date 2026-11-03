#!/usr/bin/env python3
"""Lab persp3 generator: tilted 3-D column charts as .docx, .pptx and .xlsx.  python3 gen3.py  -> docs/"""
import io, os, sys, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'docs')
DOCX_BASE = os.environ.get('PERSP_DOCX', HERE + '/base.docx')
PPTX_BASE = os.environ.get('PERSP_PPTX', HERE + '/../../corpus/pptx/decks/oox-tdf149918_pie_textarea.pptx')

NS = ('xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')

def col(n):  # 0 -> A
    return chr(ord('A') + n)

def cats_of(o):
    n = o['ncat']
    kind = o.get('cats', 'cat')
    if kind == 'short':
        return [chr(ord('A') + i) for i in range(n)]
    if kind == 'long':
        return ['Quarterly results %d' % (i + 1) for i in range(n)]
    return ['Category %d' % (i + 1) for i in range(n)]

def val(s, i):
    return 1 + ((s * 7 + i * 13) % 40) / 10

def chart_xml(o):
    cats, ns = cats_of(o), o['nser']
    n = len(cats)
    sers = ''
    for s in range(ns):
        c = col(s + 1)
        cpts = ''.join('<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, t) for i, t in enumerate(cats))
        vpts = ''.join('<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, val(s, i)) for i in range(n))
        sers += ('<c:ser><c:idx val="%d"/><c:order val="%d"/><c:tx><c:strRef><c:f>Sheet1!$%s$1</c:f><c:strCache><c:ptCount val="1"/>'
                 '<c:pt idx="0"><c:v>Series %d</c:v></c:pt></c:strCache></c:strRef></c:tx>'
                 '<c:cat><c:strRef><c:f>Sheet1!$A$2:$A$%d</c:f><c:strCache><c:ptCount val="%d"/>%s</c:strCache></c:strRef></c:cat>'
                 '<c:val><c:numRef><c:f>Sheet1!$%s$2:$%s$%d</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val="%d"/>%s</c:numCache></c:numRef></c:val></c:ser>'
                 % (s, s, c, s + 1, n + 1, n, cpts, c, c, n + 1, n, vpts))
    v3 = '<c:view3D><c:rotX val="%d"/>' % o['rotX']
    if 'hp' in o:
        v3 += '<c:hPercent val="%d"/>' % o['hp']
    v3 += '<c:rotY val="%d"/><c:rAngAx val="0"/><c:perspective val="%d"/></c:view3D>' % (o['rotY'], o['persp'])
    delc = '<c:delete val="1"/>' if o.get('nocat') else '<c:delete val="0"/>'
    delv = '<c:delete val="1"/>' if o.get('noval') else '<c:delete val="0"/>'
    cat_ax = ('<c:catAx><c:axId val="62626816"/><c:scaling><c:orientation val="minMax"/></c:scaling>%s<c:axPos val="b"/><c:tickLblPos val="nextTo"/>'
              '<c:crossAx val="62636800"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/></c:catAx>' % delc)
    val_ax = ('<c:valAx><c:axId val="62636800"/><c:scaling><c:orientation val="minMax"/></c:scaling>%s<c:axPos val="l"/><c:majorGridlines/>'
              '<c:numFmt formatCode="General" sourceLinked="1"/><c:tickLblPos val="nextTo"/><c:crossAx val="62626816"/><c:crosses val="autoZero"/>'
              '<c:crossBetween val="between"/></c:valAx>' % delv)
    legend = '<c:legend><c:legendPos val="r"/><c:layout/></c:legend>' if o.get('legend') else ''
    border = ('<c:spPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:ln w="9525"><a:solidFill><a:srgbClr val="FF00FF"/></a:solidFill></a:ln></c:spPr>'
              if o.get('border') else '')
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<c:chartSpace %s><c:lang val="en-US"/><c:chart><c:autoTitleDeleted val="1"/>%s'
            '<c:plotArea><c:layout/><c:bar3DChart><c:barDir val="col"/><c:grouping val="%s"/><c:varyColors val="0"/>%s%s<c:shape val="box"/>'
            '<c:axId val="62626816"/><c:axId val="62636800"/><c:axId val="0"/></c:bar3DChart>%s%s</c:plotArea>%s<c:plotVisOnly val="1"/></c:chart>%s'
            '<c:externalData r:id="rId1"/></c:chartSpace>'
            % (NS, v3, o.get('grouping', 'clustered'), sers, '' if o.get('grouping', 'clustered') == 'clustered' else '<c:overlap val="100"/>',
               cat_ax, val_ax, legend, border))

def xlsx_bytes(o):
    cats, ns = cats_of(o), o['nser']
    rows = '<row r="1"><c r="A1" t="inlineStr"><is><t></t></is></c>' + ''.join(
        '<c r="%s1" t="inlineStr"><is><t>Series %d</t></is></c>' % (col(s + 1), s + 1) for s in range(ns)) + '</row>'
    for i, t in enumerate(cats):
        rows += '<row r="%d"><c r="A%d" t="inlineStr"><is><t>%s</t></is></c>' % (i + 2, i + 2, t) + ''.join(
            '<c r="%s%d"><v>%s</v></c>' % (col(s + 1), i + 2, val(s, i)) for s in range(ns)) + '</row>'
    return rows

def sheet_book(o, with_chart):
    """A workbook: Sheet1 with the data; with_chart adds the chart on it (xlsx files) or not (embedded workbook)."""
    rows = xlsx_bytes(o)
    drawing = '<pageSetup orientation="portrait" scale="100"/><drawing r:id="rId1"/>' if with_chart else ''
    z = io.BytesIO()
    with zipfile.ZipFile(z, 'w', zipfile.ZIP_DEFLATED) as f:
        ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
              '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
              '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
              '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>')
        if with_chart:
            ct += ('<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>'
                   '<Override PartName="/xl/charts/chart1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>')
        f.writestr('[Content_Types].xml', ct + '</Types>')
        f.writestr('_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
        f.writestr('xl/workbook.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                   'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>')
        f.writestr('xl/_rels/workbook.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>')
        f.writestr('xl/worksheets/sheet1.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                   'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheetData>%s</sheetData>%s</worksheet>' % (rows, drawing))
        if with_chart:
            f.writestr('xl/worksheets/_rels/sheet1.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                       '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/></Relationships>')
            # The chart sits at B2, 432 x 252 pt.
            f.writestr('xl/drawings/drawing1.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
                       'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><xdr:oneCellAnchor><xdr:from><xdr:col>1</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>1</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>'
                       '<xdr:ext cx="5486400" cy="3200400"/><xdr:graphicFrame macro=""><xdr:nvGraphicFramePr><xdr:cNvPr id="2" name="Chart 1"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr>'
                       '<xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">'
                       '<c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="rId1"/>'
                       '</a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:oneCellAnchor></xdr:wsDr>')
            f.writestr('xl/drawings/_rels/drawing1.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                       '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart1.xml"/></Relationships>')
    return z.getvalue()

def write_xlsx(o, path):
    # Excel's own chart refers to its sheet: no externalData.
    cx = chart_xml(o).replace('<c:externalData r:id="rId1"/>', '')
    z = io.BytesIO(sheet_book(o, True))
    src = zipfile.ZipFile(z)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as out:
        for n in src.namelist():
            out.writestr(n, src.read(n))
        out.writestr('xl/charts/chart1.xml', cx)

def write_docx(o, path):
    src = zipfile.ZipFile(DOCX_BASE)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as out:
        for n in src.namelist():
            if n == 'word/charts/chart1.xml':
                out.writestr(n, chart_xml(o))
            elif n.startswith('word/embeddings/'):
                out.writestr(n, sheet_book(o, False))
            elif n == 'word/document.xml':
                out.writestr(n, src.read(n).decode().replace('6858000', '5486400').replace('4114800', '3200400').encode())
            else:
                out.writestr(n, src.read(n))

def write_pptx(o, path):
    src = zipfile.ZipFile(PPTX_BASE)
    slide = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
             'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree>'
             '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
             '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="2" name="Chart 1"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>'
             '<p:xfrm><a:off x="457200" y="457200"/><a:ext cx="5486400" cy="3200400"/></p:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">'
             '<c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" r:id="rId2"/></a:graphicData></a:graphic></p:graphicFrame></p:spTree></p:cSld>'
             '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as out:
        for n in src.namelist():
            d = src.read(n)
            if n == 'ppt/slides/slide1.xml':
                d = slide.encode()
            elif n == 'ppt/slides/_rels/slide1.xml.rels':
                d = d.decode().replace('</Relationships>', '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart1.xml"/></Relationships>').encode()
            elif n == '[Content_Types].xml':
                d = d.decode().replace('</Types>', '<Default Extension="xlsx" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"/>'
                                       '<Override PartName="/ppt/charts/chart1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/></Types>').encode()
            elif n == 'docProps/thumbnail.jpeg':
                continue
            elif n == '_rels/.rels':
                d = d.decode()
                import re
                d = re.sub(r'<Relationship [^>]*thumbnail[^>]*/>', '', d).encode()
            out.writestr(n, d)
        out.writestr('ppt/charts/chart1.xml', chart_xml(o))
        out.writestr('ppt/charts/_rels/chart1.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                     '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/package" Target="../embeddings/Microsoft_Excel_Worksheet1.xlsx"/></Relationships>')
        out.writestr('ppt/embeddings/Microsoft_Excel_Worksheet1.xlsx', sheet_book(o, False))

BASE = dict(rotX=30, rotY=40, persp=30, nser=3, ncat=4, legend=True)

def v(**k):
    d = dict(BASE); d.update(k); return d

AXES_OFF = dict(nocat=True, noval=True, legend=False)
SPEC = {}
# L: labels and turn, axes and legend as lab persp
SPEC['L-v30-70-nolegend'] = v(rotY=70, legend=False)
SPEC['L-v30-70-short'] = v(rotY=70, cats='short')
SPEC['L-v30-70-long'] = v(rotY=70, cats='long')
SPEC['L-v30-70-noval'] = v(rotY=70, noval=True)
SPEC['L-v30-70-nocat'] = v(rotY=70, nocat=True)
SPEC['L-v15-60'] = v(rotX=15, rotY=60)
SPEC['L-v30-55'] = v(rotY=55)
SPEC['L-v30-85'] = v(rotY=85)
SPEC['L-v30-100'] = v(rotY=100)
SPEC['L-v30-70-c8'] = v(rotY=70, ncat=8)
SPEC['L-v30-70-c2'] = v(rotY=70, ncat=2)
SPEC['L-v30-40-nolegend'] = v(legend=False)
SPEC['L-v15-40-short'] = v(rotX=15, cats='short')
# S: shape by series and category counts, axes and legend deleted as lab persp2
for ns in (1, 2, 4, 5, 6, 8):
    SPEC['S-s%dc4' % ns] = v(nser=ns, **AXES_OFF)
for nc in (2, 3, 6, 8):
    SPEC['S-s3c%d' % nc] = v(ncat=nc, **AXES_OFF)
SPEC['S-s6c2'] = v(nser=6, ncat=2, **AXES_OFF)
SPEC['S-s1-hp50'] = v(nser=1, hp=50, **AXES_OFF)
SPEC['S-s6-hp100'] = v(nser=6, hp=100, **AXES_OFF)
for ns in (2, 3, 4):
    SPEC['S-stack-s%d' % ns] = v(nser=ns, grouping='stacked', **AXES_OFF)
SPEC['S-pstack-s3'] = v(grouping='percentStacked', **AXES_OFF)
# F: the same chart in all three formats (magenta border on the chart space)
FORMATS = {
    'F-v30-40': v(),
    'F-v30-70': v(rotY=70),
    'F-v15-20': v(rotX=15, rotY=20),
    'F-v30-40-bare': v(**AXES_OFF),
    'F-v30-40-hp50': v(hp=50, **AXES_OFF),
    'F-v30-40-s6': v(nser=6, **AXES_OFF),
    'F-v30-40-short': v(cats='short'),
}

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for name, o in SPEC.items():
        write_docx(o, '%s/persp3-%s.docx' % (OUT, name))
    for name, o in FORMATS.items():
        o = dict(o, border=True)
        write_docx(o, '%s/persp3-%s.docx' % (OUT, name))
        write_pptx(o, '%s/persp3-%s.pptx' % (OUT, name))
        write_xlsx(o, '%s/persp3-%s.xlsx' % (OUT, name))
    print(len(os.listdir(OUT)), 'files')
