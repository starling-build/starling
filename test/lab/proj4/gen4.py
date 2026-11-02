#!/usr/bin/env python3
"""Lab proj4 (for amd-opus): the plot room of a 3-D chart WITHOUT its axis labels, view by view — proj3's box
apart from the labels round it. Source as proj3: lo-5afb2204's chart2 (surface3D, 4 x 3, perspective 0), its
floor, side wall and back wall outlined in 1pt black, alone on its page; surface only; the same 16 views.
Two sets of 16 pages: A every axis deleted (c:delete 1 on catAx, valAx, serAx) and no legend; B the same with the
legend kept (bottom). Page = set * 16 + view index + 1 (A first).
Measure as proj3: meas2.py outlines (FW=480 FH=360, the chart anchored where proj3's was) and meas3.py words.
gen4.py SRC.docx OUTDIR -> OUTDIR/proj4.docx   (SRC = test/corpus/docx/lo/docs/lo-5afb2204….docx)"""
import sys, os, re, zipfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen3w

VIEWS = gen3w.VIEWS
SETS = ['A', 'B']

def combos():
    return [(s, rx, ry) for s in SETS for rx, ry in VIEWS]

def variant(c, s, rx, ry):
    c = gen3w.variant(c, 'surface', rx, ry)
    for ax in ('catAx', 'valAx', 'serAx'):
        c = re.sub(r'(<c:%s>.*?<c:delete val=")0(")' % ax, r'\g<1>1\2', c, count=1, flags=re.S)
    if s == 'A':
        c = re.sub(r'<c:legend>.*?</c:legend>', '', c, flags=re.S)
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
    with zipfile.ZipFile(os.path.join(out, 'proj4.docx'), 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in zin.namelist():
            data = zin.read(n)
            if n == 'word/document.xml': data = d.encode('utf-8')
            elif n == 'word/_rels/document.xml.rels': data = rels.encode('utf-8')
            elif n == '[Content_Types].xml': data = ct.encode('utf-8')
            zo.writestr(n, data)
        rel2 = zin.read('word/charts/_rels/chart2.xml.rels') if 'word/charts/_rels/chart2.xml.rels' in zin.namelist() else None
        for k, (s, rx, ry) in enumerate(cb):
            zo.writestr('word/charts/p%d.xml' % k, variant(chart2, s, rx, ry))
            if rel2 is not None:
                xl = re.search(rb'Target="\.\./embeddings/([^"]+)"', rel2).group(1).decode()
                zo.writestr('word/embeddings/p%d.xlsx' % k, zin.read('word/embeddings/' + xl))
                zo.writestr('word/charts/_rels/p%d.xml.rels' % k, rel2.replace(xl.encode(), b'p%d.xlsx' % k))
    print(len(cb), 'pages')
