#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR - lab pielabel6 (follow-up to pielabel5; advisor: the spec rules A and B do not fit). SRC = lo-f9b9a8fc47c97aa6.docx. Names pl6-TAG.docx: w359_25 etc. (0.25 pt steps over 359-360.5 and 366-367.5), w240..w260 and w470..w490 (every 2 pt: do the layout flips repeat), noK-w360/w367 (all labels but K, K=2,3,7,8), rev-w350/w360/w367 (category names reversed datalabel8..1). For every print: label centres (meas.py) and the leader lines (leaders.py).
which labels have a leader line = grey 2-segment strokes starting on the rim). SRC = test/corpus/docx/lo/docs/lo-f9b9a8fc47c97aa6.docx.
Spec: docs/plans/pie-labels.md "The one lab that separates the two rules left".
Names pl6-<tag>.docx:  only5-w350/w360 (label 5 alone: every other label c:delete),  p45-w350/w360 (labels 4 and 5 only),
 w350 ... w370 (all 8 labels, frame width 350..370 pt in 1 pt steps; height unchanged 212.25 pt),
 no6-w350/w360 (all but label 6), no1-w350/w360 (all but label 1)  [the spec's follow-ups if neither jumps]."""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart0 = z.read('word/charts/chart1.xml').decode('utf8'); doc0 = z.read('word/document.xml').decode('utf8')
def make(tag, w, keep=None, drop=None, rev=False):
    c = chart0; d = doc0
    idxs = [k for k in range(8) if (keep is not None and (k + 1) not in keep) or (drop is not None and (k + 1) in drop)]
    dl = ''.join('<c:dLbl><c:idx val="%d"/><c:delete val="1"/></c:dLbl>' % k for k in idxs)
    i = c.find('<c:dLbls>') + len('<c:dLbls>'); c = c[:i] + dl + c[i:]
    if rev:
        for k in range(8): c = c.replace('datalabel%d' % (k + 1), 'DLTMP%d' % (8 - k))
        c = c.replace('DLTMP', 'datalabel')
    cx = int(w * 12700)
    d = d.replace('<wp:extent cx="4572000" cy="2695575"/>', '<wp:extent cx="%d" cy="2695575"/>' % cx)
    d = re.sub(r'(<a:ext cx=")4572000(" cy=")2695575(")', lambda m: '%s%d%s2695575%s' % (m.group(1), cx, m.group(2), m.group(3)), d)
    o = zipfile.ZipFile('%s/pl6-%s.docx' % (out, tag), 'w', zipfile.ZIP_DEFLATED)
    for it in z.infolist():
        data = z.read(it.filename)
        if it.filename == 'word/charts/chart1.xml': data = c.encode('utf8')
        if it.filename == 'word/document.xml': data = d.encode('utf8')
        o.writestr(it.filename, data)
    o.close()
for w in (359, 359.25, 359.5, 359.75, 360, 360.25, 360.5, 366, 366.25, 366.5, 366.75, 367, 367.25, 367.5): make('w%s' % str(w).replace('.', '_'), w)
for w in range(240, 261, 2): make('w%d' % w, w)
for w in range(470, 491, 2): make('w%d' % w, w)
for k in (2, 3, 7, 8):
    for w in (360, 367): make('no%d-w%d' % (k, w), w, drop=[k])
for w in (350, 360, 367): make('rev-w%d' % w, w, rev=True)
