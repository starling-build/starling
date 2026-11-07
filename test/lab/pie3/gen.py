#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR - lab pie3 (amd-1, 2026-11-07): does Word's flat-pie radius law R = 55.62 * cos(d) (lab pie1, 8 slices:
d = angle from firstSliceAng mod 45 to the nearer of 15 and 30) depend on the slice COUNT?
SRC = test/corpus/docx/lo/docs/lo-f9b9a8fc47c97aa6.docx (pie1's base: 360 x 212.25 pt, legend at the foot, 'datalabelK, 2' labels 9 pt).
Names p3-n<N>-a<ANG>.docx: N equal slices (2, 5, 8, 12) at firstSliceAng ANG (0,5,10,15,20,25,30,35,40,45); p3-n<N>-a<ANG>-nolab.docx: same
with no data labels (N 5 and 8, ANG 0 / 10 / 20 / 30): are labels really out of it?
Measure with test/lab/pielabel4/fit.py (pie centre and radius from the PDF), one TSV: name, N, ANG, radius, centre."""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart0 = z.read('word/charts/chart1.xml').decode('utf8')
def accent(i):
    a = 'accent%d' % (i % 6 + 1)
    return '<a:schemeClr val="%s"/>' % a if i < 6 else '<a:schemeClr val="%s"><a:lumMod val="60000"/></a:schemeClr>' % a
def make(n, ang, nolab=False):
    c = chart0
    dpts = ''.join('<c:dPt><c:idx val="%d"/><c:bubble3D val="0"/><c:spPr><a:solidFill>%s</a:solidFill><a:ln w="19050"><a:solidFill><a:schemeClr val="lt1"/></a:solidFill></a:ln></c:spPr></c:dPt>' % (i, accent(i)) for i in range(n))
    i0 = c.find('<c:dPt>'); i1 = c.rfind('</c:dPt>') + len('</c:dPt>')
    c = c[:i0] + dpts + c[i1:]
    cat = '<c:cat><c:strRef><c:f>Munka1!$A$1:$A$%d</c:f><c:strCache><c:ptCount val="%d"/>%s</c:strCache></c:strRef></c:cat>' % (n, n, ''.join('<c:pt idx="%d"><c:v>datalabel%d</c:v></c:pt>' % (i, i + 1) for i in range(n)))
    val = '<c:val><c:numRef><c:f>Munka1!$B$1:$B$%d</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val="%d"/>%s</c:numCache></c:numRef></c:val>' % (n, n, ''.join('<c:pt idx="%d"><c:v>2</c:v></c:pt>' % i for i in range(n)))
    c = re.sub(r'<c:cat>.*?</c:cat>', lambda m: cat, c, count=1, flags=re.S)
    c = re.sub(r'<c:val>.*?</c:val>', lambda m: val, c, count=1, flags=re.S)
    assert 'firstSliceAng val="0"' in c
    c = c.replace('firstSliceAng val="0"', 'firstSliceAng val="%d"' % ang)
    if nolab:
        for tag in ('showVal', 'showCatName', 'showPercent', 'showSerName', 'showLegendKey'):
            c = re.sub(r'<c:%s val="1"/>' % tag, '<c:%s val="0"/>' % tag, c)
    name = 'p3-n%d-a%d%s' % (n, ang, '-nolab' if nolab else '')
    o = zipfile.ZipFile('%s/%s.docx' % (out, name), 'w', zipfile.ZIP_DEFLATED)
    for it in z.infolist():
        data = z.read(it.filename)
        if it.filename == 'word/charts/chart1.xml': data = c.encode('utf8')
        o.writestr(it.filename, data)
    o.close()
cnt = 0
for n in (2, 5, 8, 12):
    for a in (0, 5, 10, 15, 20, 25, 30, 35, 40, 45): make(n, a); cnt += 1
for n in (5, 8):
    for a in (0, 10, 20, 30): make(n, a, True); cnt += 1
print(cnt, 'documents')
