#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR - lab pie2 (lenovo-2, 2026-11-07): what moves Word's best-fit pie labels when nothing is near them.
SRC = test/corpus/docx/lo/docs/lo-f9b9a8fc47c97aa6.docx. Names p2-<tag>.docx:
  noleg-wN / legr-wN / notitle-wN : all 8 labels, frame width N pt (356-376, 1 pt steps) with the legend removed / at the right /
                                    the title removed. Lab pie1 found the layout changes with the width in whole px (A<=479, B 480-488,
                                    C 489+) with no label near anything; if the bands move or vanish, the legend or title is the cause.
  copies-<set>  : THREE identical charts in one document (pair 1-2; lone label 1; all 8), one under the other: does state carry over?
  tri-I-J-K, quad-...: three/four labels at ang 0 (pairs in pie1 moved labels 10-36 px): do the moves add, max, or neither.
  one22-wN      : lone label 1 (22.5 deg) at widths 350-370: does a lone erratic label depend on the width / pixel phase.
  len1-N, len5-N: lone label 1 / label 5 with a category name of N characters (d1, d1xx, ...): is the drift in px or in box widths.
  pair-1-2-aA, pair-1-5-aA: those pairs at firstSliceAng A = 5, 10, 15 (off the flat zone).
Measure on windows: python meas2.py DIR > PIE2-WORD.tsv (labels AND leaders, several charts per page)."""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart0 = z.read('word/charts/chart1.xml').decode('utf8'); doc0 = z.read('word/document.xml').decode('utf8')
rels0 = z.read('word/_rels/document.xml.rels').decode('utf8'); ct0 = z.read('[Content_Types].xml').decode('utf8')
crels0 = z.read('word/charts/_rels/chart1.xml.rels').decode('utf8')
def chart_xml(keep=None, ang=0, legend='b', title=True, names=None):
    c = chart0
    if keep is not None:
        dl = ''.join('<c:dLbl><c:idx val="%d"/><c:delete val="1"/></c:dLbl>' % k for k in range(8) if (k + 1) not in keep)
        i = c.find('<c:dLbls>') + len('<c:dLbls>'); c = c[:i] + dl + c[i:]
    c = c.replace('firstSliceAng val="0"', 'firstSliceAng val="%d"' % ang)
    if legend is None: c = re.sub(r'<c:legend>.*?</c:legend>', '', c, flags=re.S)
    else: c = c.replace('<c:legendPos val="b"/>', '<c:legendPos val="%s"/>' % legend)
    if not title: c = re.sub(r'<c:title>.*?</c:title>', '', c, flags=re.S).replace('<c:autoTitleDeleted val="0"/>', '<c:autoTitleDeleted val="1"/>')
    for k, n in (names or {}).items(): c = c.replace('<c:v>datalabel%d</c:v>' % k, '<c:v>%s</c:v>' % n)
    return c
def make(tag, w=360, charts=None, **kw):
    """charts: list of chart xml strings (one per copy, stacked); default one chart from kw."""
    charts = charts or [chart_xml(**kw)]
    d = doc0; rels = rels0; ct = ct0
    cx = int(w * 12700)
    d = d.replace('<wp:extent cx="4572000" cy="2695575"/>', '<wp:extent cx="%d" cy="2695575"/>' % cx)
    d = re.sub(r'(<a:ext cx=")4572000(" cy=")2695575(")', lambda m: '%s%d%s2695575%s' % (m.group(1), cx, m.group(2), m.group(3)), d)
    # more copies: duplicate the paragraph holding the drawing, pointing at chart2.xml, chart3.xml
    m = re.search(r'<w:p [^>]*>(?:(?!<w:p ).)*?<w:drawing>.*?</w:drawing>.*?</w:p>', d, re.S); para = m.group(0)
    extra = ''
    for i in range(2, len(charts) + 1):
        p = para.replace('r:id="rId6"', 'r:id="rId%d"' % (90 + i)).replace('<wp:docPr id="1"', '<wp:docPr id="%d"' % i)
        p = re.sub(r'<w:bookmark(Start|End)[^>]*/>', '', p)
        extra += p
        rels = rels.replace('</Relationships>', '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="charts/chart%d.xml"/></Relationships>' % (90 + i, i))
        ct = ct.replace('</Types>', '<Override PartName="/word/charts/chart%d.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/></Types>' % i)
    d = d.replace(para, para + extra, 1)
    o = zipfile.ZipFile('%s/p2-%s.docx' % (out, tag), 'w', zipfile.ZIP_DEFLATED)
    for it in z.infolist():
        data = z.read(it.filename)
        if it.filename == 'word/charts/chart1.xml': data = charts[0].encode('utf8')
        if it.filename == 'word/document.xml': data = d.encode('utf8')
        if it.filename == 'word/_rels/document.xml.rels': data = rels.encode('utf8')
        if it.filename == '[Content_Types].xml': data = ct.encode('utf8')
        o.writestr(it.filename, data)
    for i in range(2, len(charts) + 1):
        o.writestr('word/charts/chart%d.xml' % i, charts[i - 1].encode('utf8'))
        o.writestr('word/charts/_rels/chart%d.xml.rels' % i, crels0.encode('utf8'))
    o.close()
n = 0
for w in range(356, 377):
    make('noleg-w%d' % w, w, legend=None); make('legr-w%d' % w, w, legend='r'); make('notitle-w%d' % w, w, title=False); n += 3
for tag, keep in (('pair12', [1, 2]), ('one22', [1]), ('all', None)):
    make('copies-%s' % tag, charts=[chart_xml(keep=keep)] * 3); n += 1
for s in ((1, 2, 3), (1, 2, 5), (1, 4, 5), (1, 2, 4), (4, 5, 6), (1, 5, 8), (2, 4, 5), (1, 2, 4, 5), (1, 4, 5, 8)):
    make(('tri-' if len(s) == 3 else 'quad-') + '-'.join(map(str, s)), keep=list(s)); n += 1
for w in range(350, 371): make('one22-w%d' % w, w, keep=[1]); n += 1
for L in (2, 4, 6, 8, 12, 16, 20):
    make('len1-%d' % L, keep=[1], names={1: 'd1' + 'x' * (L - 2)}); make('len5-%d' % L, keep=[5], names={5: 'd5' + 'x' * (L - 2)}); n += 2
for a in (5, 10, 15):
    make('pair-1-2-a%d' % a, keep=[1, 2], ang=a); make('pair-1-5-a%d' % a, keep=[1, 5], ang=a); n += 2
print(n, 'docs')
