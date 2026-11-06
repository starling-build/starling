# lab piewid: the pielabel3 base pie with frame width 300..600 step 50 (250 and 480 exist in pielabel3)
#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR — lab pielabel3 (for windows: Word prints, then meas.py): lo-f9b9a8fc's flat pie (8 equal slices, bestFit
"category, value" labels 9pt, legend at the bottom, 360 x 212 pt inline) with ONE thing varied per document.
Question (lab pieeq found it only at 8 slices + legend bottom): Word stands label 5 (slice 5, lower left) 8 pt HIGHER than label 4, its mirror.
What does that depend on? The room under the pie (height), the width, the label size, the legend's rows (size), the slice count,
where the slices start (firstSliceAng), whether the label has a value, and the order of the names.
Names: pl3-<tag>.docx. Tags: base, h200/h230/h300/h360 (frame height pt), w250/w480 (width), lab7/lab11 (label pt), leg6/leg14 (legend pt),
n7/n9 (slices), ang22/ang45 (firstSliceAng), cat (category only), rev (names datalabel8..1)."""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart0 = z.read('word/charts/chart1.xml').decode('utf8'); doc0 = z.read('word/document.xml').decode('utf8')
def accent(i):
    a = 'accent%d' % (i % 6 + 1)
    return '<a:schemeClr val="%s"/>' % a if i < 6 else '<a:schemeClr val="%s"><a:lumMod val="%d"/></a:schemeClr>' % (a, 60000 if i < 12 else 40000)
def make(tag, n=8, h=None, w=None, lab=None, leg=None, ang=None, cat=False, rev=False):
    c = chart0; d = doc0
    dpts = ''.join('<c:dPt><c:idx val="%d"/><c:bubble3D val="0"/><c:spPr><a:solidFill>%s</a:solidFill><a:ln w="19050"><a:solidFill><a:schemeClr val="lt1"/></a:solidFill></a:ln><a:effectLst/></c:spPr></c:dPt>' % (i, accent(i)) for i in range(n))
    c = re.sub(r'(<c:dPt>.*</c:dPt>)', lambda m: dpts, c, count=1, flags=re.S)
    names = ['datalabel%d' % (i + 1) for i in range(n)]
    if rev: names.reverse()
    cat_x = '<c:cat><c:strRef><c:f>Munka1!$A$1:$A$%d</c:f><c:strCache><c:ptCount val="%d"/>%s</c:strCache></c:strRef></c:cat>' % (n, n, ''.join('<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, names[i]) for i in range(n)))
    val = '<c:val><c:numRef><c:f>Munka1!$B$1:$B$%d</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val="%d"/>%s</c:numCache></c:numRef></c:val>' % (n, n, ''.join('<c:pt idx="%d"><c:v>2</c:v></c:pt>' % i for i in range(n)))
    c = re.sub(r'<c:cat>.*?</c:cat>', lambda m: cat_x, c, count=1, flags=re.S)
    c = re.sub(r'<c:val>.*?</c:val>', lambda m: val, c, count=1, flags=re.S)
    i = c.find('<c:dLbls>'); j = c.find('</c:dLbls>', i)
    blk = c[i:j]
    if lab: blk = blk.replace('sz="900"', 'sz="%d"' % (lab * 100))
    if cat: blk = blk.replace('<c:showVal val="1"/>', '<c:showVal val="0"/>')
    c = c[:i] + blk + c[j:]
    if leg:
        k = c.find('<c:legend>'); c = c[:k] + c[k:].replace('sz="900"', 'sz="%d"' % (leg * 100), 1)
    if ang is not None: c = re.sub(r'<c:firstSliceAng val="\d+"/>', '<c:firstSliceAng val="%d"/>' % ang, c)
    if h or w:
        cx, cy = 4572000, 2695575
        if w: cx = int(w * 12700)
        if h: cy = int(h * 12700)
        d = d.replace('<wp:extent cx="4572000" cy="2695575"/>', '<wp:extent cx="%d" cy="%d"/>' % (cx, cy))
        d = re.sub(r'(<a:ext cx=")4572000(" cy=")2695575(")', lambda m: '%s%d%s%d%s' % (m.group(1), cx, m.group(2), cy, m.group(3)), d)
    o = zipfile.ZipFile('%s/pw-%s.docx' % (out, tag), 'w', zipfile.ZIP_DEFLATED)
    for it in z.infolist():
        data = z.read(it.filename)
        if it.filename == 'word/charts/chart1.xml': data = c.encode('utf8')
        if it.filename == 'word/document.xml': data = d.encode('utf8')
        o.writestr(it.filename, data)
    o.close()
for w in (300, 350, 400, 450, 500, 550, 600): make('w%d' % w, w=w)
