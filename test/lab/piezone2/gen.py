#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR - lab piezone2 (lenovo-2, 2026-11-07): the partner sweep of lab piezone with its controls (advisor round 2), and the sweep extended.
SRC = lo-f9b9a8fc47c97aa6.docx. A zone label is one whose slice middle is 13-30 degrees from the vertical axis; only such labels
move when other labels exist (lab pie2). Names pz2-<tag>.docx (three slices: slice 1 = 0-45 with its label at 22.5, slice 2 = 45..45+2s, slice 3 the rest, labels deleted as said; values print as three digits):
  both-sSS   : labels 1 and 2 (the pair), s = 5..145 by 2.5 (partner middle 50..190 degrees; 50-135 repeats lab piezone's sweep).
  one-sSS    : label 1 alone in the same geometry (does the lone zone label move with slices 2 and 3's angles?).
  two-sSS    : label 2 alone (the partner's own place; "frozen" partners in single-spot sectors).
Measure on windows: python meas2.py DIR > PIEZONE2-WORD.tsv."""
import sys, re, zipfile, uuid
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart0 = z.read('word/charts/chart1.xml').decode('utf8'); doc0 = z.read('word/document.xml').decode('utf8')
rels0 = z.read('word/_rels/document.xml.rels').decode('utf8'); ct0 = z.read('[Content_Types].xml').decode('utf8')
crels0 = z.read('word/charts/_rels/chart1.xml.rels').decode('utf8')
def series(c, vals, names=None):
    n = len(vals)
    def cut(block, texts):
        pts = ''.join('<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, t) for i, t in enumerate(texts))
        block = re.sub(r'(<c:ptCount val=")\d+(")', lambda m: '%s%d%s' % (m.group(1), n, m.group(2)), block)
        return re.sub(r'(<c:ptCount val="\d+"/>).*?(</c:(?:strCache|numCache)>)', lambda m: m.group(1) + pts + m.group(2), block, flags=re.S)
    names = names or ['datalabel%d' % (i + 1) for i in range(n)]
    c = re.sub(r'<c:cat>.*?</c:cat>', lambda m: cut(m.group(0), names), c, flags=re.S)
    c = re.sub(r'<c:val>.*?</c:val>', lambda m: cut(m.group(0), ['%g' % v for v in vals]), c, flags=re.S)
    return c
def chart_xml(vals=None, names=None, keep=None, ang=0, noval=False):
    c = chart0
    if vals is not None or names is not None: c = series(c, vals or [2] * 8, names)
    n = len(vals) if vals else 8
    if keep is not None:
        dl = ''.join('<c:dLbl><c:idx val="%d"/><c:delete val="1"/></c:dLbl>' % k for k in range(n) if (k + 1) not in keep)
        i = c.find('<c:dLbls>') + len('<c:dLbls>'); c = c[:i] + dl + c[i:]
    if noval:   # (the sweep's values are angles: three digits each, so every label is as wide as the next: "datalabel1, 045")
        i = c.find('<c:spPr>', c.find('<c:dLbls>')); c = c[:i] + '<c:numFmt formatCode="000" sourceLinked="0"/>' + c[i:]
    return c.replace('firstSliceAng val="0"', 'firstSliceAng val="%d"' % ang)
def make(tag, w=360, charts=None, **kw):
    charts = charts or [chart_xml(**kw)]
    d = doc0; rels = rels0; ct = ct0
    cx = int(round(w * 12700))
    d = d.replace('<wp:extent cx="4572000" cy="2695575"/>', '<wp:extent cx="%d" cy="2695575"/>' % cx)
    d = re.sub(r'(<a:ext cx=")4572000(" cy=")2695575(")', lambda m: '%s%d%s2695575%s' % (m.group(1), cx, m.group(2), m.group(3)), d)
    m = re.search(r'<w:p [^>]*>(?:(?!<w:p ).)*?<w:drawing>.*?</w:drawing>.*?</w:p>', d, re.S); para = m.group(0)
    extra = ''; parts = {}
    for i in range(2, len(charts) + 1):
        p = para.replace('r:id="rId6"', 'r:id="rId%d"' % (90 + i)).replace('<wp:docPr id="1" name="Diagram 1"', '<wp:docPr id="%d" name="Diagram %d"' % (i, i))
        p = re.sub(r'<w:bookmark(Start|End)[^>]*/>', '', p)
        p = re.sub(r'wp14:anchorId="[0-9A-F]+"', 'wp14:anchorId="%08X"' % (0x7D38FBEC + i), p)
        p = re.sub(r'wp14:editId="[0-9A-F]+"', 'wp14:editId="%08X"' % (0x52B65842 + i), p)
        p = re.sub(r'id="\{[0-9A-F-]+\}"', 'id="{%s}"' % str(uuid.uuid4()).upper(), p)
        extra += p
        rels = rels.replace('</Relationships>', '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="charts/chart%d.xml"/></Relationships>' % (90 + i, i))
        ct = ct.replace('</Types>', ('<Override PartName="/word/charts/chart%d.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>'
                                     '<Override PartName="/word/charts/style%d.xml" ContentType="application/vnd.ms-office.chartstyle+xml"/>'
                                     '<Override PartName="/word/charts/colors%d.xml" ContentType="application/vnd.ms-office.chartcolorstyle+xml"/></Types>') % (i, i, i))
        parts['word/charts/chart%d.xml' % i] = charts[i - 1]
        parts['word/charts/_rels/chart%d.xml.rels' % i] = crels0.replace('colors1.xml', 'colors%d.xml' % i).replace('style1.xml', 'style%d.xml' % i)
        parts['word/charts/style%d.xml' % i] = z.read('word/charts/style1.xml').decode('utf8')
        parts['word/charts/colors%d.xml' % i] = z.read('word/charts/colors1.xml').decode('utf8')
    d = d.replace(para, para + extra, 1)
    o = zipfile.ZipFile('%s/pz2-%s.docx' % (out, tag), 'w', zipfile.ZIP_DEFLATED)
    for it in z.infolist():
        data = z.read(it.filename)
        if it.filename == 'word/charts/chart1.xml': data = charts[0].encode('utf8')
        if it.filename == 'word/document.xml': data = d.encode('utf8')
        if it.filename == 'word/_rels/document.xml.rels': data = rels.encode('utf8')
        if it.filename == '[Content_Types].xml': data = ct.encode('utf8')
        o.writestr(it.filename, data)
    for k, v in parts.items(): o.writestr(k, v.encode('utf8'))
    o.close()
n = 0
for s2 in [x / 2 for x in range(10, 291, 5)]:
    span2 = 2 * s2; vals = [45, span2, 360 - 45 - span2]
    make('both-s%05.1f' % s2, vals=vals, keep=[1, 2], noval=True); make('one-s%05.1f' % s2, vals=vals, keep=[1], noval=True); make('two-s%05.1f' % s2, vals=vals, keep=[2], noval=True); n += 3
print(n, 'docs')
