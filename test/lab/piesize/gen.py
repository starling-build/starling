#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR — lab piesize (for windows: Word prints, then test/lab/pielabel4/fit.py on the PDFs gives each print's pie
centre and radius; meas.py's label centres too). Question: what does Word shrink a flat pie's radius for, when its data labels stand
outside it? Base: lo-f9b9a8fc's chart (360 x 212 pt inline, title, bestFit "category, value" labels 9 pt, legend at the foot) with FIVE
equal slices named 'label1'..; ONE thing changed per document: label text length, slice count, label font size, legend place,
label position, label content, a manual inner/outer plot layout, the frame size, no title. Names: ps-<variable>-<value>.docx."""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart0 = z.read('word/charts/chart1.xml').decode('utf8')
doc0 = z.read('word/document.xml').decode('utf8')
def accent(i):
    a = 'accent%d' % (i % 6 + 1)
    return '<a:schemeClr val="%s"/>' % a if i < 6 else '<a:schemeClr val="%s"><a:lumMod val="%d"/></a:schemeClr>' % (a, 60000 if i < 12 else 40000)
def make(name, n=5, length=6, size=900, legend='b', pos='bestFit', content='cv', layout=None, frame=(4572000, 2695575), title=True):
    c = chart0
    vals = [100 // n] * n
    vals[0] += 100 - sum(vals)
    names = [('label%d' % (i + 1)).ljust(length, 'x')[:max(length, len('label%d' % (i + 1)))] if length > 6 else 'label%d' % (i + 1) for i in range(n)]
    if length > 6: names = [('label%d_' % (i + 1) + 'x' * 99)[:length] for i in range(n)]
    if length < 6: names = [('L%d' % (i + 1)) for i in range(n)]
    dpts = ''.join('<c:dPt><c:idx val="%d"/><c:bubble3D val="0"/><c:spPr><a:solidFill>%s</a:solidFill><a:ln w="19050"><a:solidFill><a:schemeClr val="lt1"/></a:solidFill></a:ln><a:effectLst/></c:spPr></c:dPt>' % (i, accent(i)) for i in range(n))
    c = re.sub(r'(<c:dPt>.*</c:dPt>)', lambda mm: dpts, c, count=1, flags=re.S)
    cat = '<c:cat><c:strRef><c:f>Munka1!$A$1:$A$%d</c:f><c:strCache><c:ptCount val="%d"/>%s</c:strCache></c:strRef></c:cat>' % (n, n, ''.join('<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, names[i]) for i in range(n)))
    val = '<c:val><c:numRef><c:f>Munka1!$B$1:$B$%d</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val="%d"/>%s</c:numCache></c:numRef></c:val>' % (n, n, ''.join('<c:pt idx="%d"><c:v>%d</c:v></c:pt>' % (i, v) for i, v in enumerate(vals)))
    c = re.sub(r'<c:cat>.*?</c:cat>', lambda mm: cat, c, count=1, flags=re.S)
    c = re.sub(r'<c:val>.*?</c:val>', lambda mm: val, c, count=1, flags=re.S)
    c = re.sub(r'<c:firstSliceAng val="\d+"/>', '<c:firstSliceAng val="0"/>', c)
    c = c.replace('<c:dLblPos val="bestFit"/>', '<c:dLblPos val="%s"/>' % pos)
    i0 = c.find('<c:dLbls>'); i1 = c.find('</c:dLbls>') + 10
    d = c[i0:i1].replace('sz="900"', 'sz="%d"' % size)
    sv, sc, sp = {'cv': (1, 1, 0), 'v': (1, 0, 0), 'p': (0, 0, 1)}[content]
    d = re.sub(r'<c:showVal val="\d"/>', '<c:showVal val="%d"/>' % sv, d)
    d = re.sub(r'<c:showCatName val="\d"/>', '<c:showCatName val="%d"/>' % sc, d)
    d = re.sub(r'<c:showPercent val="\d"/>', '<c:showPercent val="%d"/>' % sp, d)
    c = c[:i0] + d + c[i1:]
    if legend is None: c = re.sub(r'<c:legend>.*?</c:legend>', '', c, count=1, flags=re.S)
    else: c = c.replace('<c:legendPos val="b"/>', '<c:legendPos val="%s"/>' % legend)
    if not title:
        c = re.sub(r'<c:title>.*?</c:title>', '', c, count=1, flags=re.S)
        c = c.replace('<c:autoTitleDeleted val="0"/>', '<c:autoTitleDeleted val="1"/>')
    if layout:
        t, x, y, w, h = layout
        ml = '<c:layout><c:manualLayout><c:layoutTarget val="%s"/><c:xMode val="edge"/><c:yMode val="edge"/><c:x val="%s"/><c:y val="%s"/><c:w val="%s"/><c:h val="%s"/></c:manualLayout></c:layout>' % (t, x, y, w, h)
        c = c.replace('<c:plotArea><c:layout/>', '<c:plotArea>' + ml, 1)
    doc = re.sub(r'<wp:extent cx="\d+" cy="\d+"/>', '<wp:extent cx="%d" cy="%d"/>' % frame, doc0, count=1)
    o = zipfile.ZipFile('%s/ps-%s.docx' % (out, name), 'w', zipfile.ZIP_DEFLATED)
    for it in z.infolist():
        data = z.read(it.filename)
        if it.filename == 'word/charts/chart1.xml': data = c.encode('utf8')
        if it.filename == 'word/document.xml': data = doc.encode('utf8')
        o.writestr(it.filename, data)
    o.close()
make('base')
for L in (2, 14, 24, 40): make('len-%d' % L, length=L)
for n in (2, 3, 8, 12): make('n-%d' % n, n=n)
for s in (600, 1200, 1600, 2400): make('sz-%d' % (s // 100), size=s)
for g, nm in ((None, 'none'), ('r', 'r'), ('t', 't'), ('l', 'l')): make('leg-%s' % nm, legend=g)
for p in ('outEnd', 'inEnd', 'ctr'): make('pos-%s' % p, pos=p)
for ct in ('v', 'p'): make('content-%s' % ct, content=ct)
make('lay-in60', layout=('inner', 0.2, 0.2, 0.6, 0.6))
make('lay-in40', layout=('inner', 0.3, 0.3, 0.4, 0.4))
make('lay-in60-none', layout=('inner', 0.2, 0.2, 0.6, 0.6), legend=None)
make('lay-out', layout=('outer', 0.1, 0.1, 0.8, 0.8))
for fr in ((3810000, 3810000), (6096000, 3810000), (3048000, 2032000)): make('fr-%dx%d' % (fr[0] // 12700, fr[1] // 12700), frame=fr)
make('notitle', title=False)
