#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR - lab pie1 (lenovo-2, 2026-11-07): Word's best-fit pie label placement, one and two labels at a time.
SRC = test/corpus/docx/lo/docs/lo-f9b9a8fc47c97aa6.docx (8 equal slices, 'datalabelK, 2' labels 9 pt, legend at the foot,
frame 360 x 212.25 pt; Word's pie R 53.76 at that frame whatever the labels). Names p1-<tag>.docx:
  one-aNNN  : ONLY label 1 (every other label c:delete), firstSliceAng NNN, so the one label's slice middle is at NNN + 22.5
              degrees clockwise from twelve: 5-degree grid (NNN = 0, 5, ... 355) plus 1- and 2-degree scans where the anchor
              rule turns (its corner / edge / centre sectors).
  pair-I-J  : only labels I and J (I < J, index order = placement order), firstSliceAng 0: all 28 pairs.
  w<N>      : all 8 labels, frame width N pt (370-450 in 4-pt steps), height unchanged: how many layouts past 367.
Measure on windows: meas.py DIR > PIE1-WORD.tsv and leaders.py DIR > LEADERS1-WORD.tsv (both here; pymupdf)."""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart0 = z.read('word/charts/chart1.xml').decode('utf8'); doc0 = z.read('word/document.xml').decode('utf8')
assert 'firstSliceAng val="0"' in chart0
def make(tag, w=360, keep=None, ang=0):
    c = chart0; d = doc0
    if keep is not None:
        dl = ''.join('<c:dLbl><c:idx val="%d"/><c:delete val="1"/></c:dLbl>' % k for k in range(8) if (k + 1) not in keep)
        i = c.find('<c:dLbls>') + len('<c:dLbls>'); c = c[:i] + dl + c[i:]
    c = c.replace('firstSliceAng val="0"', 'firstSliceAng val="%d"' % ang)
    cx = int(w * 12700)
    d = d.replace('<wp:extent cx="4572000" cy="2695575"/>', '<wp:extent cx="%d" cy="2695575"/>' % cx)
    d = re.sub(r'(<a:ext cx=")4572000(" cy=")2695575(")', lambda m: '%s%d%s2695575%s' % (m.group(1), cx, m.group(2), m.group(3)), d)
    o = zipfile.ZipFile('%s/p1-%s.docx' % (out, tag), 'w', zipfile.ZIP_DEFLATED)
    for it in z.infolist():
        data = z.read(it.filename)
        if it.filename == 'word/charts/chart1.xml': data = c.encode('utf8')
        if it.filename == 'word/document.xml': data = d.encode('utf8')
        o.writestr(it.filename, data)
    o.close()
angs = set(range(0, 360, 5))
for lo, hi, step in ((350, 365, 1), (35, 43, 1), (77, 103, 2), (122, 148, 2), (167, 178, 1), (212, 223, 1), (257, 283, 2), (302, 328, 2)):
    angs |= set(a % 360 for a in range(lo, hi + 1, step))
for a in sorted(angs): make('one-a%03d' % a, keep=[1], ang=a)
for i in range(1, 9):
    for j in range(i + 1, 9): make('pair-%d-%d' % (i, j), keep=[i, j])
for w in range(370, 451, 4): make('w%d' % w, w=w)
print(len(angs), 'single,', 28, 'pairs,', len(range(370, 451, 4)), 'widths')
