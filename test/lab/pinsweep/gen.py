#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR - lab pinsweep (advisor round 4, lenovo-2, 2026-11-07): is Word's single-label best-fit place in the
13-30 degree zone a smooth function of the geometry (then write the lone rule first) or a chaotic step search (then stop chasing
an exact rule)? SRC = lo-f9b9a8fc47c97aa6.docx. Three slices: a filler f, the LABELLED 45-degree slice (index 2, the only label), the
rest; firstSliceAng 348 so the labelled slice's middle m = f + 10.5 runs 12..31 by 0.5 (f = 1.5..20.5), and the mirror image with
firstSliceAng 300, f = 37.5 - m (middle at 360 - m). Each angle twice: auto, and PINNED (c:manualLayout x=0 y=0 = Word's default).
Pinned-only extras: middles 35, 45, 55, 80, 100, 135 (span 45), and 22.5 with spans 30 and 60 (the default law in general).
Values print as three digits (numFmt 000) so every label has one width. Names ps-<m>-<auto|pin>[-mir].docx, ps-def-<m>-s<span>.docx.
NOTE: the filler boundary moves the pie path's Bezier control-point bound with m (up to 1.035 R): measure R from the on-curve apex
(meas2.py does) and read anchors against the bound where it matters.
Measure: python meas2.py DIR > PINSWEEP-WORD.tsv"""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart0 = z.read('word/charts/chart1.xml').decode('utf8')
def series(c, vals):
    n = len(vals)
    def cut(block, texts):
        pts = ''.join('<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, t) for i, t in enumerate(texts))
        block = re.sub(r'(<c:ptCount val=")\d+(")', lambda m: '%s%d%s' % (m.group(1), n, m.group(2)), block)
        return re.sub(r'(<c:ptCount val="\d+"/>).*?(</c:(?:strCache|numCache)>)', lambda m: m.group(1) + pts + m.group(2), block, flags=re.S)
    c = re.sub(r'<c:cat>.*?</c:cat>', lambda m: cut(m.group(0), ['datalabel%d' % (i + 1) for i in range(n)]), c, flags=re.S)
    return re.sub(r'<c:val>.*?</c:val>', lambda m: cut(m.group(0), ['%g' % v for v in vals]), c, flags=re.S)
def make(tag, vals, ang, keep, pin=False):
    c = series(chart0, vals)
    dl = ''
    for k in range(len(vals)):
        if (k + 1) != keep: dl += '<c:dLbl><c:idx val="%d"/><c:delete val="1"/></c:dLbl>' % k
        elif pin: dl += ('<c:dLbl><c:idx val="%d"/><c:layout><c:manualLayout><c:x val="0.0"/><c:y val="0.0"/></c:manualLayout></c:layout>'
                         '<c:showLegendKey val="0"/><c:showVal val="1"/><c:showCatName val="1"/><c:showSerName val="0"/><c:showPercent val="0"/><c:showBubbleSize val="0"/></c:dLbl>') % k
    i = c.find('<c:dLbls>') + len('<c:dLbls>'); c = c[:i] + dl + c[i:]
    i = c.find('<c:spPr>', c.find('<c:dLbls>')); c = c[:i] + '<c:numFmt formatCode="000" sourceLinked="0"/>' + c[i:]
    c = c.replace('firstSliceAng val="0"', 'firstSliceAng val="%d"' % ang)
    o = zipfile.ZipFile('%s/ps-%s.docx' % (out, tag), 'w', zipfile.ZIP_DEFLATED)
    for it in z.infolist():
        data = z.read(it.filename)
        if it.filename == 'word/charts/chart1.xml': data = c.encode('utf8')
        o.writestr(it.filename, data)
    o.close()
n = 0
for m2 in range(24, 63):                       # m = 12.0 .. 31.0 by 0.5
    m = m2 / 2; f = m - 10.5; fm = 37.5 - m
    for pin in (False, True):
        make('%04.1f-%s' % (m, 'pin' if pin else 'auto'), [f, 45, 315 - f], 348, 2, pin); n += 1
        make('%04.1f-%s-mir' % (m, 'pin' if pin else 'auto'), [fm, 45, 315 - fm], 300, 2, pin); n += 1
for m in (35, 45, 55, 80, 100, 135):
    make('def-%03d-s45' % m, [m - 10.5, 45, 315 - (m - 10.5)], 348, 2, True); n += 1
for span in (30, 60):
    make('def-022.5-s%d' % span, [22.5 - span / 2 + 12, span, 360 - span - (22.5 - span / 2 + 12)], 348, 2, True); n += 1
print(n, 'docs')
