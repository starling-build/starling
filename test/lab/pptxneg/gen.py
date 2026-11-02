#!/usr/bin/env python3
"""Lab for aascu 5864 slide 8: a column chart with negative values, 20 pt bold category
labels that wrap to two lines, 16 pt bold value labels and a legend at the right.
PowerPoint's print leaves the plot 4.7 pt higher at the foot than ours, draws a
value-axis line, and stands the value labels 14.85 pt off the plot (ours 11.1).
Each variant is the whole 5864 deck with only ppt/charts/chart3.xml (slide 8) changed;
print PAGE 8 ONLY of each. Variants (id -> what differs from the original):
  orig-*       : unchanged (tickLblPos low, long category names, 20/16 pt)
  t-<pos>-<n>  : category axis tickLblPos low|nextTo|high  x  names long (two lines) | short (one line)
  pos-<pos>-long : the values made all positive (is it the negative values?)
  c<N>-<pos>-<n> : category label size N pt
  v<N>-...     : value label size N pt
Usage: gen.py SRC.pptx OUTDIR
"""
import re, sys, zipfile, os
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
orig = z.read('ppt/charts/chart3.xml').decode('utf8')
SHORT = ['Low', 'Mid', 'High']

def variant(pos='low', names='long', positive=False, cat=2000, val=1600):
    s = orig
    cx = re.search(r'<c:catAx>.*?</c:catAx>', s, re.S).group(0)
    c2 = re.sub(r'<c:tickLblPos val="\w+"/>', f'<c:tickLblPos val="{pos}"/>', cx)
    c2 = c2.replace('sz="2000"', f'sz="{cat}"')
    s = s.replace(cx, c2)
    vx = re.search(r'<c:valAx>.*?</c:valAx>', s, re.S).group(0)
    s = s.replace(vx, vx.replace('sz="1600"', f'sz="{val}"'))
    if names == 'short':
        for i, n in enumerate(SHORT):
            s = re.sub(r'(<c:cat>.*?<c:pt idx="%d"><c:v>)[^<]*' % i, r'\g<1>' + n, s, count=1, flags=re.S)
    if positive:
        s = re.sub(r'<c:v>-([\d.]+)</c:v>', r'<c:v>\1</c:v>', s)
    return s

V = {'orig-low-long': {}}
for pos in ('low', 'nextTo', 'high'):
    for n in ('long', 'short'):
        V[f't-{pos}-{n}'] = dict(pos=pos, names=n)
for pos in ('low', 'nextTo'):
    V[f'pos-{pos}-long'] = dict(pos=pos, positive=True)
for c in (1000, 1400):
    V[f'c{c//100}-low-long'] = dict(cat=c)
    V[f'c{c//100}-nextTo-short'] = dict(cat=c, pos='nextTo', names='short')
for v in (1000, 2400):
    V[f'v{v//100}-low-long'] = dict(val=v)
for vid, kw in V.items():
    xml = variant(**kw)
    dst = os.path.join(out, f'pptxneg-{vid}.pptx')
    with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as o:
        for it in z.infolist():
            o.writestr(it.filename, xml.encode('utf8') if it.filename == 'ppt/charts/chart3.xml' else z.read(it.filename))
    print(dst)
