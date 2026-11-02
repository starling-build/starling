#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR — lab pieeq: lo-f9b9a8fc's flat pie (bestFit labels "category, value", 9pt) with N equal slices
(6/8/10/12) and the legend at the bottom, on the right, or none. Names: pieeq-<n>-<b|r|none>.docx
Question: where Word stands each outside label (bestFit) of N equal slices, in particular the pair about six o'clock —
lo-f9b9a8fc's eight put "datalabel5, 2" 8pt higher than "datalabel4, 2", the mirror of it."""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart = z.read('word/charts/chart1.xml').decode('utf8')
def accent(i):
    a = 'accent%d' % (i % 6 + 1)
    return '<a:schemeClr val="%s"/>' % a if i < 6 else '<a:schemeClr val="%s"><a:lumMod val="%d"/></a:schemeClr>' % (a, 60000 if i < 12 else 40000)
for n in (6, 8, 10, 12):
    for leg in ('b', 'r', 'none'):
        c = chart
        dpts = ''.join('<c:dPt><c:idx val="%d"/><c:bubble3D val="0"/><c:spPr><a:solidFill>%s</a:solidFill><a:ln w="19050"><a:solidFill><a:schemeClr val="lt1"/></a:solidFill></a:ln><a:effectLst/></c:spPr></c:dPt>' % (i, accent(i)) for i in range(n))
        c = re.sub(r'(<c:dPt>.*</c:dPt>)', lambda m: dpts, c, count=1, flags=re.S)
        cat = '<c:cat><c:strRef><c:f>Munka1!$A$1:$A$%d</c:f><c:strCache><c:ptCount val="%d"/>%s</c:strCache></c:strRef></c:cat>' % (n, n, ''.join('<c:pt idx="%d"><c:v>datalabel%d</c:v></c:pt>' % (i, i + 1) for i in range(n)))
        val = '<c:val><c:numRef><c:f>Munka1!$B$1:$B$%d</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val="%d"/>%s</c:numCache></c:numRef></c:val>' % (n, n, ''.join('<c:pt idx="%d"><c:v>2</c:v></c:pt>' % i for i in range(n)))
        c = re.sub(r'<c:cat>.*?</c:cat>', lambda m: cat, c, count=1, flags=re.S)
        c = re.sub(r'<c:val>.*?</c:val>', lambda m: val, c, count=1, flags=re.S)
        if leg == 'none':
            c = re.sub(r'<c:legend>.*?</c:legend>', '', c, flags=re.S)
        else:
            c = c.replace('<c:legendPos val="b"/>', '<c:legendPos val="%s"/>' % leg)
        o = zipfile.ZipFile('%s/pieeq-%d-%s.docx' % (out, n, leg), 'w', zipfile.ZIP_DEFLATED)
        for i in z.infolist():
            d = z.read(i.filename)
            if i.filename == 'word/charts/chart1.xml': d = c.encode('utf8')
            o.writestr(i.filename, d)
        o.close()
