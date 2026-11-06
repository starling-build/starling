#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR — lab pielabel4 (for windows: Word prints, then meas.py as in pielabel3): lo-f9b9a8fc's flat pie (bestFit
"category, value" labels 9pt, legend at the bottom, 360 x 212 pt inline), but with M thin slices of D degrees side by side, their
group centred at PHI degrees clockwise from twelve o'clock (set with firstSliceAng, so the thin slices are 1..M), and ONE big slice
(M+1) for the rest. Values are the degrees (D each, 360-M*D for the big one), so the labels read "datalabel1, 4".
Question: where Word stands a label that collides with its neighbour's (the rims of two thin slices are R*D/57.3 apart, 1 to 6 pt, a
label is 11 pt high), and which way it pushes: along the rim, away from the group's centre, down, outward? Compare with the
single-label rule of lab pielabel3 (against the rim). Names: pl4-<phi>-<m>-<d>.docx (phi 0 top, 90 right, 180 foot, 270 left)."""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart0 = z.read('word/charts/chart1.xml').decode('utf8')
def accent(i):
    a = 'accent%d' % (i % 6 + 1)
    return '<a:schemeClr val="%s"/>' % a if i < 6 else '<a:schemeClr val="%s"><a:lumMod val="%d"/></a:schemeClr>' % (a, 60000 if i < 12 else 40000)
def make(phi, m, d):
    c = chart0; n = m + 1
    vals = [d] * m + [360 - m * d]
    dpts = ''.join('<c:dPt><c:idx val="%d"/><c:bubble3D val="0"/><c:spPr><a:solidFill>%s</a:solidFill><a:ln w="19050"><a:solidFill><a:schemeClr val="lt1"/></a:solidFill></a:ln><a:effectLst/></c:spPr></c:dPt>' % (i, accent(i)) for i in range(n))
    c = re.sub(r'(<c:dPt>.*</c:dPt>)', lambda mm: dpts, c, count=1, flags=re.S)
    cat = '<c:cat><c:strRef><c:f>Munka1!$A$1:$A$%d</c:f><c:strCache><c:ptCount val="%d"/>%s</c:strCache></c:strRef></c:cat>' % (n, n, ''.join('<c:pt idx="%d"><c:v>datalabel%d</c:v></c:pt>' % (i, i + 1) for i in range(n)))
    val = '<c:val><c:numRef><c:f>Munka1!$B$1:$B$%d</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val="%d"/>%s</c:numCache></c:numRef></c:val>' % (n, n, ''.join('<c:pt idx="%d"><c:v>%d</c:v></c:pt>' % (i, v) for i, v in enumerate(vals)))
    c = re.sub(r'<c:cat>.*?</c:cat>', lambda mm: cat, c, count=1, flags=re.S)
    c = re.sub(r'<c:val>.*?</c:val>', lambda mm: val, c, count=1, flags=re.S)
    start = (phi - m * d // 2) % 360
    c = re.sub(r'<c:firstSliceAng val="\d+"/>', '<c:firstSliceAng val="%d"/>' % start, c)
    o = zipfile.ZipFile('%s/pl4-%d-%d-%d.docx' % (out, phi, m, d), 'w', zipfile.ZIP_DEFLATED)
    for it in z.infolist():
        data = z.read(it.filename)
        if it.filename == 'word/charts/chart1.xml': data = c.encode('utf8')
        o.writestr(it.filename, data)
    o.close()
for phi, m, d in [(90, 3, 2), (90, 3, 4), (90, 3, 8), (90, 2, 4), (90, 4, 4), (270, 3, 4),
                  (0, 3, 2), (0, 3, 4), (0, 3, 8), (180, 3, 2), (180, 3, 4), (180, 3, 8), (45, 3, 4), (135, 3, 4), (225, 3, 4), (315, 3, 4)]:
    make(phi, m, d)
