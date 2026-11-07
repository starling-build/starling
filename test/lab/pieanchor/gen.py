#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR - lab pieanchor (lenovo-2, 2026-11-07): on which radius does Word anchor a best-fit pie label?
Lab pie1 put a lone label's box corner exactly on the point at R x 1.0346 (the 45-degree arcs' Bezier control-point extent),
not on the drawn circle, when the slice boundaries were off the axes. For other slice counts the control-point bounding box
is not square (5 equal slices: 1.085 R across, 1.064 R up and down). SRC = lo-f9b9a8fc47c97aa6.docx; the series is cut to N
equal slices (values 2), ONE label kept (label 1, or the label whose middle is nearest the bottom), firstSliceAng A stepping
through one slice so the lone label walks round a quarter turn. Names pa3-nN-aA-kK.docx. Measure: python meas2.py DIR > PIEANCHOR-WORD.tsv
(gives the fitz label box and the wedge-box R; the TRUE radius comes from a circle fit of the on-curve wedge vertices, fit.py)."""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart0 = z.read('word/charts/chart1.xml').decode('utf8')
def series(c, n):
    # cut c:cat and c:val to n points
    def cut(block):
        pts = re.findall(r'<c:pt idx="\d+">.*?</c:pt>', block, re.S)
        keep = ''.join(pts[:n])
        block = re.sub(r'(<c:ptCount val=")\d+(")', lambda m: '%s%d%s' % (m.group(1), n, m.group(2)), block)
        return re.sub(r'(<c:ptCount val="\d+"/>).*?(</c:(?:strCache|numCache)>)', lambda m: m.group(1) + keep + m.group(2), block, flags=re.S)
    c = re.sub(r'<c:cat>.*?</c:cat>', lambda m: cut(m.group(0)), c, flags=re.S)
    c = re.sub(r'<c:val>.*?</c:val>', lambda m: cut(m.group(0)), c, flags=re.S)
    return c
def make(tag, n, ang, keep):
    c = series(chart0, n)
    dl = ''.join('<c:dLbl><c:idx val="%d"/><c:delete val="1"/></c:dLbl>' % k for k in range(n) if (k + 1) != keep)
    i = c.find('<c:dLbls>') + len('<c:dLbls>'); c = c[:i] + dl + c[i:]
    c = c.replace('firstSliceAng val="0"', 'firstSliceAng val="%d"' % ang)
    o = zipfile.ZipFile('%s/pa3-%s.docx' % (out, tag), 'w', zipfile.ZIP_DEFLATED)
    for it in z.infolist():
        data = z.read(it.filename)
        if it.filename == 'word/charts/chart1.xml': data = c.encode('utf8')
        o.writestr(it.filename, data)
    o.close()
cnt = 0
for n in (3, 5, 6, 12):
    span = 360 // n
    for a in range(0, span, max(1, span // 8)):
        make('n%d-a%03d-k1' % (n, a), n, a, 1); cnt += 1
        kb = min(range(1, n + 1), key=lambda k: abs(((a + span * (k - 0.5)) % 360) - 180))   # the slice nearest the bottom
        if kb != 1: make('n%d-a%03d-k%d' % (n, a, kb), n, a, kb); cnt += 1
print(cnt, 'docs')
