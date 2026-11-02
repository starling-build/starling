#!/usr/bin/env python3
"""Lab pieout (for amd-opus): the OUTLINE of Word's 3-D pie — top face and rim — by tilt, perspective, depth and height.
Source: amd-1's lab pieeq document (lo-f9b9a8fc's chart, 360 x 212.25pt inline frame), made a 3-D pie of ONE slice
(value 1, accent1, no outline), no title, no legend, no labels, so the picture is a lone disc: its top face one light
colour, its rim a darker shade of it. One page per variant (VARIANTS below: rotX, perspective, depthPercent, hPercent).
Read (meas.py): in the picture, the disc's left/right extremes, and down its middle column the top face's far edge,
its near edge (where the rim's darker colour starts) and the rim's bottom.
gen.py OUT.docx [N]   (N: only the first N pages, to bisect)"""
import sys, re, zipfile, os
HERE = os.path.dirname(os.path.abspath(__file__))
VARIANTS = [(rx, p, None, None) for p in (0, 30, 60) for rx in (10, 20, 30, 45, 60, 75)] + \
           [(30, 30, 50, None), (30, 30, 200, None), (30, 30, None, 50), (30, 30, None, 200)]
def chart(base, rx, persp, depth, h):
    c = base
    c = re.sub(r'<c:title>.*?</c:title>', '', c, flags=re.S).replace('<c:autoTitleDeleted val="0"/>', '<c:autoTitleDeleted val="1"/>')
    c = re.sub(r'<c:legend>.*?</c:legend>', '', c, flags=re.S)
    v3 = '<c:view3D><c:rotX val="%d"/><c:rotY val="0"/>%s%s<c:rAngAx val="0"/><c:perspective val="%d"/></c:view3D>' % (
        rx, '' if depth is None else '<c:depthPercent val="%d"/>' % depth, '' if h is None else '<c:hPercent val="%d"/>' % h, persp)
    c = c.replace('<c:plotArea>', v3 + '<c:plotArea>', 1)
    c = c.replace('<c:pieChart>', '<c:pie3DChart>').replace('</c:pieChart>', '</c:pie3DChart>')
    c = re.sub(r'<c:firstSliceAng[^>]*/>', '', c)
    ser = re.search(r'<c:ser>.*?</c:ser>', c, flags=re.S).group(0)
    s = re.sub(r'<c:dPt>.*</c:dPt>', '<c:dPt><c:idx val="0"/><c:bubble3D val="0"/><c:spPr><a:solidFill><a:schemeClr val="accent1"/></a:solidFill><a:ln><a:noFill/></a:ln></c:spPr></c:dPt>', ser, count=1, flags=re.S)
    s = re.sub(r'<c:dLbls>.*?</c:dLbls>', '', s, flags=re.S)
    s = re.sub(r'<c:cat>.*?</c:cat>', '<c:cat><c:strRef><c:f>Munka1!$A$1:$A$1</c:f><c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>a</c:v></c:pt></c:strCache></c:strRef></c:cat>', s, count=1, flags=re.S)
    s = re.sub(r'<c:val>.*?</c:val>', '<c:val><c:numRef><c:f>Munka1!$B$1:$B$1</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val="1"/><c:pt idx="0"><c:v>1</c:v></c:pt></c:numCache></c:numRef></c:val>', s, count=1, flags=re.S)
    c = c.replace(ser, s)
    c = re.sub(r'<c:dLbls>.*?</c:dLbls>', '', c, flags=re.S)
    return c
if __name__ == '__main__':
    out = sys.argv[1]
    z = zipfile.ZipFile(os.path.join(HERE, 'src.docx'))
    doc = z.read('word/document.xml').decode('utf-8')
    base = z.read('word/charts/chart1.xml').decode('utf-8')
    runs = re.findall(r'<w:r>(?:(?!</w:r>).)*?</w:r>', doc, re.S)
    keep = [r for r in runs if '<c:chart ' in r]
    assert len(keep) == 1, len(keep)
    rid = re.search(r'r:id="([^"]+)"', keep[0]).group(1)
    npages = int(sys.argv[2]) if len(sys.argv) > 2 else len(VARIANTS)
    # (Each drawing its own docPr id.)
    body = ''.join('<w:p><w:pPr>%s</w:pPr>%s</w:p>' % ('' if k == 0 else '<w:pageBreakBefore/>',
                   re.sub(r'(<wp:docPr id=")\d+(")', r'\g<1>%d\2' % (100 + k), keep[0].replace('r:id="%s"' % rid, 'r:id="rIdP%d"' % k))) for k in range(npages))
    d = re.sub(r'<w:body>.*<w:sectPr', lambda m: '<w:body>' + body + '<w:sectPr', doc, count=1, flags=re.S)
    rels = z.read('word/_rels/document.xml.rels').decode('utf-8')
    rels = rels.replace('</Relationships>', ''.join('<Relationship Id="rIdP%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="charts/p%d.xml"/>' % (k, k) for k in range(npages)) + '</Relationships>')
    ct = z.read('[Content_Types].xml').decode('utf-8')
    ct = ct.replace('</Types>', ''.join('<Override PartName="/word/charts/p%d.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>' % k for k in range(npages)) + '</Types>')
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in z.namelist():
            if n == 'word/document.xml': zo.writestr(n, d)
            elif n == 'word/_rels/document.xml.rels': zo.writestr(n, rels)
            elif n == '[Content_Types].xml': zo.writestr(n, ct)
            else: zo.writestr(n, z.read(n))
        for k, v in enumerate(VARIANTS[:npages]):
            zo.writestr('word/charts/p%d.xml' % k, chart(base, *v))
            # (Each chart part its own rels with the external workbook only: a chartStyle and chartColorStyle part
            # shared by 22 charts made Word refuse the file.)
            rel = z.read('word/charts/_rels/chart1.xml.rels').decode('utf-8')
            rel = re.sub(r'<Relationship [^>]*(chartColorStyle|chartStyle)"[^>]*/>', '', rel)
            zo.writestr('word/charts/_rels/p%d.xml.rels' % k, rel)
    print(npages, 'pages ->', out)
