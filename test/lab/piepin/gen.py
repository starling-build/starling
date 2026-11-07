#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR - lab piepin (lenovo-2, 2026-11-07): which labels Word places again when one is pinned.
SRC = lo-f9b9a8fc47c97aa6.docx (8 equal slices, frame 360 pt: Word's layout B, label 5 moved with a leader). One label K gets a
c:dLbl with a c:layout/c:manualLayout (an offset from its automatic place, as a share of the chart: Word writes that when a
label is dragged), the other seven stay automatic. Names pp-kK-<tag>.docx:
  pp-kK-zero   : manualLayout x=0 y=0 (pinned where it is: does a pinned label still take part in the others' placement?)
  pp-kK-right  : x=+0.03 (about 11 pt right)      pp-kK-up : y=-0.05 (about 11 pt up)
  pp-kK-far    : y=-0.25 for labels under the horizontal, +0.25 for those above (taken well away from its neighbours)
  pp-base      : nothing pinned (a repeat of layout B).
Measure on windows: python meas2.py DIR > PIEPIN-WORD.tsv (labels and leaders)."""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart0 = z.read('word/charts/chart1.xml').decode('utf8')
def make(tag, k=None, x=0.0, y=0.0):
    c = chart0
    if k is not None:
        dl = ('<c:dLbl><c:idx val="%d"/><c:layout><c:manualLayout><c:x val="%s"/><c:y val="%s"/></c:manualLayout></c:layout>'
              '<c:showLegendKey val="0"/><c:showVal val="1"/><c:showCatName val="1"/><c:showSerName val="0"/><c:showPercent val="0"/>'
              '<c:showBubbleSize val="0"/></c:dLbl>') % (k - 1, repr(x), repr(y))
        i = c.find('<c:dLbls>') + len('<c:dLbls>'); c = c[:i] + dl + c[i:]
    o = zipfile.ZipFile('%s/pp-%s.docx' % (out, tag), 'w', zipfile.ZIP_DEFLATED)
    for it in z.infolist():
        data = z.read(it.filename)
        if it.filename == 'word/charts/chart1.xml': data = c.encode('utf8')
        o.writestr(it.filename, data)
    o.close()
make('base'); n = 1
for k in range(1, 9):
    make('k%d-zero' % k, k, 0.0, 0.0); make('k%d-right' % k, k, 0.03, 0.0); make('k%d-up' % k, k, 0.0, -0.05)
    make('k%d-far' % k, k, 0.0, -0.25 if k in (3, 4, 5, 6) else 0.25); n += 4
print(n, 'docs')
