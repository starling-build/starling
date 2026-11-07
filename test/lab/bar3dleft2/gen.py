#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR - lab bar3dleft2 (follow-up to bar3dleft, which gave Word's 3-D wall for a chart WITH a placed value-axis title).
SRC = test/corpus/docx/docs/zh-b8de3ae2....docx. Each docx is ONE page with that doc's chart 3 alone (2 series x 5 categories, rotX 15 rotY 20,
rAngAx 1, legend at the foot, chart title), with the axis titles varied:
  nt = NO value-axis title (the title element removed), at = value-axis title "千元" with NO manual layout (auto position),
  ct = no value-axis title, a category-axis title "類別" only, pt = the original (placed) value title, for the control.
Shapes: bl (536.5 x 356.2 pt, as is), w400, w560 (frame width), h260, h400 (frame height); label widths: v1000 (values x1000), v1e-4 (/10000).
Names b3m-KIND-SHAPE.docx (KIND nt|at|ct, SHAPE bl|w400|w560|h260|h400|v1000|v1e-4) plus b3m-pt-bl. The measure, as bar3dleft: back-wall left x0 and right x1
(grey ~215 gridline), tick labels' left/right, frame rect."""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart0 = z.read('word/charts/chart3.xml').decode('utf8'); doc0 = z.read('word/document.xml').decode('utf8')
paras = re.findall(r'<w:p[ >](?:(?!</w:p>).)*?</w:p>', doc0, re.S)
para = [p for p in paras if 'r:id="rId14"' in p][0]
head = doc0[:doc0.find('<w:body>') + len('<w:body>')]
sect = '<w:sectPr><w:pgSz w:w="11910" w:h="16840"/><w:pgMar w:top="1580" w:right="320" w:bottom="280" w:left="200" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>'
def scale(c, f):
    def sv(m):
        v = float(m.group(1)) * f
        return '<c:v>%s</c:v>' % (('%d' % round(v)) if v >= 10 else repr(round(v, 3)))
    def blk(m): return re.sub(r'<c:v>([0-9.]+)</c:v>', sv, m.group(0))
    return re.sub(r'<c:val>.*?</c:val>', blk, c, flags=re.S)
CAT = '<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="zh-TW"/><a:t>類別</a:t></a:r></a:p></c:rich></c:tx><c:overlay val="0"/></c:title>'
def titles(c, kind):
    m = re.search(r'<c:valAx>.*?</c:valAx>', c, re.S); va = m.group(0)
    t = re.search(r'<c:title>.*?</c:title>', va, re.S).group(0)
    if kind in ('nt', 'ct'): va2 = va.replace(t, '')
    elif kind == 'at': va2 = va.replace(t, re.sub(r'<c:layout>.*?</c:layout>', '<c:layout/>', t, flags=re.S))
    else: va2 = va
    c = c.replace(va, va2)
    if kind == 'ct':
        m = re.search(r'<c:catAx>.*?</c:catAx>', c, re.S); ca = m.group(0)
        assert '<c:title>' not in ca
        ca2 = ca.replace('<c:numFmt', CAT + '<c:numFmt', 1)
        c = c.replace(ca, ca2)
    return c
def make(tag, kind, f=None, w=None, h=None):
    c = titles(chart0, kind); p = para
    if f: c = scale(c, f)
    e = re.search(r'<wp:extent cx="(\d+)" cy="(\d+)"/>', p)
    cx, cy = int(e.group(1)), int(e.group(2))
    if w: cx = int(w * 12700)
    if h: cy = int(h * 12700)
    p = p.replace(e.group(0), '<wp:extent cx="%d" cy="%d"/>' % (cx, cy))
    p = re.sub(r'(<a:ext cx=")\d+(" cy=")\d+(")', lambda m: '%s%d%s%d%s' % (m.group(1), cx, m.group(2), cy, m.group(3)), p)
    p = re.sub(r'<w:ind [^>]*/>', '', p)
    d = head + p + sect
    o = zipfile.ZipFile('%s/b3m-%s.docx' % (out, tag), 'w', zipfile.ZIP_DEFLATED)
    for it in z.infolist():
        data = z.read(it.filename)
        if it.filename == 'word/charts/chart3.xml': data = c.encode('utf8')
        if it.filename == 'word/document.xml': data = d.encode('utf8')
        o.writestr(it.filename, data)
    o.close()
make('pt-bl', 'pt')
for kind in ('nt', 'at', 'ct'):
    make(kind + '-bl', kind); make(kind + '-w400', kind, w=400); make(kind + '-w560', kind, w=560)
    make(kind + '-h260', kind, h=260); make(kind + '-h400', kind, h=400)
for kind in ('nt', 'at'):
    make(kind + '-v1000', kind, f=1000); make(kind + '-v1e-4', kind, f=0.0001)
