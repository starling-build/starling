#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR — lab pielabel5 (for windows: Word prints, then meas.py of pielabel3, plus a LEADER column:
which labels have a leader line = grey 2-segment strokes starting on the rim). SRC = test/corpus/docx/lo/docs/lo-f9b9a8fc47c97aa6.docx.
Spec: docs/plans/pie-labels.md "The one lab that separates the two rules left".
Names pl5-<tag>.docx:  only5-w350/w360 (label 5 alone: every other label c:delete),  p45-w350/w360 (labels 4 and 5 only),
 w350 ... w370 (all 8 labels, frame width 350..370 pt in 1 pt steps; height unchanged 212.25 pt),
 no6-w350/w360 (all but label 6), no1-w350/w360 (all but label 1)  [the spec's follow-ups if neither jumps]."""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart0 = z.read('word/charts/chart1.xml').decode('utf8'); doc0 = z.read('word/document.xml').decode('utf8')
def make(tag, w, keep=None, drop=None):
    c = chart0; d = doc0
    idxs = [k for k in range(8) if (keep is not None and (k + 1) not in keep) or (drop is not None and (k + 1) in drop)]
    dl = ''.join('<c:dLbl><c:idx val="%d"/><c:delete val="1"/></c:dLbl>' % k for k in idxs)
    i = c.find('<c:dLbls>') + len('<c:dLbls>'); c = c[:i] + dl + c[i:]
    cx = int(w * 12700)
    d = d.replace('<wp:extent cx="4572000" cy="2695575"/>', '<wp:extent cx="%d" cy="2695575"/>' % cx)
    d = re.sub(r'(<a:ext cx=")4572000(" cy=")2695575(")', lambda m: '%s%d%s2695575%s' % (m.group(1), cx, m.group(2), m.group(3)), d)
    o = zipfile.ZipFile('%s/pl5-%s.docx' % (out, tag), 'w', zipfile.ZIP_DEFLATED)
    for it in z.infolist():
        data = z.read(it.filename)
        if it.filename == 'word/charts/chart1.xml': data = c.encode('utf8')
        if it.filename == 'word/document.xml': data = d.encode('utf8')
        o.writestr(it.filename, data)
    o.close()
for w in (350, 360):
    make('only5-w%d' % w, w, keep=[5]); make('p45-w%d' % w, w, keep=[4, 5])
    make('no6-w%d' % w, w, drop=[6]); make('no1-w%d' % w, w, drop=[1])
for w in range(350, 371): make('w%d' % w, w)
