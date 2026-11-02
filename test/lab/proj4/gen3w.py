#!/usr/bin/env python3
"""Lab proj3 (for amd-opus): the plot room Word gives a 3-D chart with its axis labels and legend, view by view.
Source: lo-5afb220423472cb1's chart2 (surface3D, 4 categories x 3 series, value axis right, legend bottom), alone
on its page as in lab surf, with its floor, side wall and back wall outlined in 1pt black (as lab proj), and the
same chart as a 3-D column (bar3D standard) and a 3-D line chart. Each view one page.
Measure as lab proj (meas2.py for the outlines) AND the text: every word's box (pymupdf get_text('words')) in
frame points, so the axis labels' extents are known per view.
gen3.py SRC.docx OUTDIR -> OUTDIR/proj3.docx; page = index in combos() + 1."""
import sys, os, re, zipfile

VIEWS = [(20, 0), (20, 20), (20, 45), (20, 90), (20, 135), (20, 170), (20, 180), (20, 225), (20, 270), (20, 315),
         (0, 20), (10, 20), (30, 20), (40, 20), (60, 20), (30, 170)]
KINDS = ['surface', 'bar', 'line']

def combos():
    return [(k, rx, ry) for k in KINDS for rx, ry in VIEWS]

LN = '<c:spPr><a:noFill/><a:ln w="12700"><a:solidFill><a:srgbClr val="000000"/></a:solidFill></a:ln></c:spPr>'

def variant(c, kind, rx, ry):
    c, m = re.subn(r'<c:rotX val="-?\d+"\s*/>', '<c:rotX val="%d"/>' % rx, c); assert m == 1
    c, m = re.subn(r'<c:rotY val="\d+"\s*/>', '<c:rotY val="%d"/>' % ry, c); assert m == 1
    for wall in ('floor', 'sideWall', 'backWall'):
        c = re.sub(r'(<c:%s>.*?)<c:spPr>.*?</c:spPr>' % wall, r'\1' + LN.replace('\\', '\\\\'), c, count=1, flags=re.S)
        if LN not in re.search(r'<c:%s>.*?</c:%s>' % (wall, wall), c, re.S).group(0):
            c = c.replace('</c:%s>' % wall, LN + '</c:%s>' % wall, 1)
    if kind == 'bar':
        c = re.sub(r'<c:surface3DChart>\s*<c:wireframe val="\d"\s*/>', '<c:bar3DChart><c:barDir val="col"/><c:grouping val="standard"/><c:varyColors val="0"/>', c)
        c = re.sub(r'<c:bandFmts\s*/>|<c:bandFmts>.*?</c:bandFmts>', '<c:gapWidth val="150"/><c:shape val="box"/>', c, flags=re.S)
        c = c.replace('</c:surface3DChart>', '</c:bar3DChart>')
    elif kind == 'line':
        c = re.sub(r'<c:surface3DChart>\s*<c:wireframe val="\d"\s*/>', '<c:line3DChart><c:grouping val="standard"/><c:varyColors val="0"/>', c)
        c = re.sub(r'<c:bandFmts\s*/>|<c:bandFmts>.*?</c:bandFmts>', '', c, flags=re.S)
        c = c.replace('</c:surface3DChart>', '</c:line3DChart>')
    return c

if __name__ == "__main__":
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    zin = zipfile.ZipFile(src)
    doc = zin.read('word/document.xml').decode('utf-8')
    runs = re.findall(r'<w:r>(?:(?!</w:r>).)*?</w:r>', doc, re.S)
    keep = [r for r in runs if 'r:id="rId6"' in r]
    assert len(keep) == 1, len(keep)
    chart2 = zin.read('word/charts/chart2.xml').decode('utf-8')
    cb = combos()
    body = ''.join('<w:p><w:pPr>%s</w:pPr>%s</w:p>' % ('' if k == 0 else '<w:pageBreakBefore/>', keep[0].replace('r:id="rId6"', 'r:id="rIdP%d"' % k))
                   for k in range(len(cb)))
    d = re.sub(r'<w:body>.*<w:sectPr', '<w:body>' + body.replace('\\', '\\\\') + '<w:sectPr', doc, count=1, flags=re.S)
    rels = zin.read('word/_rels/document.xml.rels').decode('utf-8')
    rels = rels.replace('</Relationships>', ''.join('<Relationship Id="rIdP%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="charts/p%d.xml"/>' % (k, k) for k in range(len(cb))) + '</Relationships>')
    ct = zin.read('[Content_Types].xml').decode('utf-8')
    ct = ct.replace('</Types>', ''.join('<Override PartName="/word/charts/p%d.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>' % k for k in range(len(cb))) + '</Types>')
    with zipfile.ZipFile(os.path.join(out, 'proj3.docx'), 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in zin.namelist():
            data = zin.read(n)
            if n == 'word/document.xml': data = d.encode('utf-8')
            elif n == 'word/_rels/document.xml.rels': data = rels.encode('utf-8')
            elif n == '[Content_Types].xml': data = ct.encode('utf-8')
            zo.writestr(n, data)
        rel2 = zin.read('word/charts/_rels/chart2.xml.rels') if 'word/charts/_rels/chart2.xml.rels' in zin.namelist() else None
        for k, (kind, rx, ry) in enumerate(cb):
            zo.writestr('word/charts/p%d.xml' % k, variant(chart2, kind, rx, ry))
            if rel2 is not None:
                # Word refuses a package where two chart parts share one embedded workbook: give each its own copy
                xl = re.search(rb'Target="\.\./embeddings/([^"]+)"', rel2).group(1).decode()
                zo.writestr('word/embeddings/p%d.xlsx' % k, zin.read('word/embeddings/' + xl))
                zo.writestr('word/charts/_rels/p%d.xml.rels' % k, rel2.replace(xl.encode(), b'p%d.xlsx' % k))
    print(len(cb), 'pages')
