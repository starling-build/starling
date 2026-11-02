#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR — lab persp: a Word 3-D column chart (lo-8743d336's, shape box) at many camera views, frame sizes
and groupings, to turn the fitted perspective camera of OfficeApp's Chart._columns3DCamera into rules.
Names: persp-<id>.docx. Ids:
  v<rotX>-<rotY>-p<persp>   views, clustered 4 categories x 3 series, frame 432 x 252 pt
  f<w>x<h>-v<rotX>-<rotY>   frame sizes (pt), persp 30
  g<nCat>x<nSer>           groupings (cat x ser) at view 30/40/30, frame 432 x 252
  stacked, pstacked        stacked / percent-stacked 4 x 3 at 30/40/30
  gd<gapDepth>, dp<depthPercent>, hp<hPercent>   depth / height settings at 30/40/30
Questions: the room (centre, size) and the scale per view and frame; the box height as a function of nSer/nCat, grouping and
hPercent; the box depth as a function of gapDepth and depthPercent; tick count and label places at each size."""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart0 = z.read('word/charts/chart1.xml').decode('utf8')
doc0 = z.read('word/document.xml').decode('utf8')
VALS = [4.3, 2.5, 3.5, 4.5, 2.4, 4.4, 1.8, 2.8, 2, 2, 3, 5, 3.1, 1.2, 4.0, 2.2, 3.7, 1.5, 2.9, 4.1]
def col(i): return chr(ord('B') + i)
def series(ncat, nser):
    cats = ''.join('<c:pt idx="%d"><c:v>Category %d</c:v></c:pt>' % (i, i + 1) for i in range(ncat))
    s = ''
    for j in range(nser):
        vals = ''.join('<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, VALS[(i * 3 + j * 5) % len(VALS)]) for i in range(ncat))
        s += ('<c:ser><c:idx val="%d"/><c:order val="%d"/><c:tx><c:strRef><c:f>Sheet1!$%s$1</c:f><c:strCache><c:ptCount val="1"/>'
              '<c:pt idx="0"><c:v>Series %d</c:v></c:pt></c:strCache></c:strRef></c:tx><c:cat><c:strRef><c:f>Sheet1!$A$2:$A$%d</c:f>'
              '<c:strCache><c:ptCount val="%d"/>%s</c:strCache></c:strRef></c:cat><c:val><c:numRef><c:f>Sheet1!$%s$2:$%s$%d</c:f>'
              '<c:numCache><c:formatCode>General</c:formatCode><c:ptCount val="%d"/>%s</c:numCache></c:numRef></c:val></c:ser>'
              % (j, j, col(j), j + 1, ncat + 1, ncat, cats, col(j), col(j), ncat + 1, ncat, vals))
    return s
def make(name, rx=30, ry=40, p=30, w=432, h=252, ncat=4, nser=3, grouping='clustered', gapdepth=None, depthpct=None, hpct=None):
    v = '<c:view3D><c:rotX val="%d"/><c:rotY val="%d"/>' % (rx, ry)
    if hpct: v += '<c:hPercent val="%d"/>' % hpct
    if depthpct: v += '<c:depthPercent val="%d"/>' % depthpct
    v += '<c:rAngAx val="0"/><c:perspective val="%d"/></c:view3D>' % p
    c = re.sub(r'<c:view3D>.*?</c:view3D>', lambda m: v, chart0, count=1, flags=re.S)
    c = re.sub(r'<c:ser>.*</c:ser>', lambda m: series(ncat, nser), c, count=1, flags=re.S)
    c = c.replace('<c:grouping val="clustered"/>', '<c:grouping val="%s"/>' % grouping)
    if grouping != 'clustered': c = c.replace('<c:shape ', '<c:overlap val="100"/><c:shape ', 1)
    if gapdepth is not None: c = c.replace('<c:shape ', '<c:gapDepth val="%d"/><c:shape ' % gapdepth, 1)
    c = re.sub(r'<c:shape val="\w+"/>', '<c:shape val="box"/>', c)
    d = re.sub(r'<wp:extent cx="\d+" cy="\d+"/>', '<wp:extent cx="%d" cy="%d"/>' % (w * 12700, h * 12700), doc0)
    d = re.sub(r'<a:ext cx="\d+" cy="\d+"/>', '<a:ext cx="%d" cy="%d"/>' % (w * 12700, h * 12700), d)
    o = zipfile.ZipFile('%s/persp-%s.docx' % (out, name), 'w', zipfile.ZIP_DEFLATED)
    for i in z.infolist():
        data = z.read(i.filename)
        if i.filename == 'word/charts/chart1.xml': data = c.encode('utf8')
        if i.filename == 'word/document.xml': data = d.encode('utf8')
        o.writestr(i.filename, data)
    o.close()
n = 0
for rx in (15, 30, 45):
    for ry in (20, 40, 70):
        make('v%d-%d-p30' % (rx, ry), rx, ry, 30); n += 1
for rx, ry in ((30, 40), (15, 20)):
    make('v%d-%d-p60' % (rx, ry), rx, ry, 60); n += 1
make('v30-40-p0', 30, 40, 0); n += 1
for rx, ry in ((30, 40), (15, 20)):
    for w, h in ((288, 216), (540, 324)):
        make('f%dx%d-v%d-%d' % (w, h, rx, ry), rx, ry, 30, w, h); n += 1
for nc, ns in ((3, 2), (6, 2), (2, 5), (8, 1)):
    make('g%dx%d' % (nc, ns), ncat=nc, nser=ns); n += 1
make('stacked', grouping='stacked'); make('pstacked', grouping='percentStacked'); n += 2
make('gd50', gapdepth=50); make('gd300', gapdepth=300); make('dp50', depthpct=50); make('dp200', depthpct=200)
make('hp50', hpct=50); make('hp100', hpct=100); n += 6
print(n, 'docs')
