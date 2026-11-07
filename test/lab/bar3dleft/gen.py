#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR - lab bar3dleft. SRC = test/corpus/docx/docs/zh-b8de3ae2....docx.
Question: Word's 3-D column wall (back-wall left/right, depth) for a chart left to its own layout: does the
left edge follow the value labels' width and the number format's '_)' gap, the frame width and height?
Each docx is ONE page with zh-b8de3ae2's chart 3 (p12: 2 series x 5 categories, rotX 15 rotY 20, rAngAx 1,
legend at the foot, title) alone, varied: bl (as is) | nf (format '#,##0') | gap (format '#,##0_)') | gen (General)
| v1000 (values x1000) | v1e-2 (values /100) | v1e-4 (/10000) | w400 w440 w480 w520 w560 (frame width pt) |
h260 h300 h340 h400 (frame height pt) | h356-w536 is bl.  Names b3l-TAG.docx."""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart0 = z.read('word/charts/chart3.xml').decode('utf8'); doc0 = z.read('word/document.xml').decode('utf8')
FMT = '#,##0_);[Red]\\(#,##0\\)'
assert FMT in chart0
# one paragraph: the one holding r:id rId14
paras = re.findall(r'<w:p[ >](?:(?!</w:p>).)*?</w:p>', doc0, re.S)
para = [p for p in paras if 'r:id="rId14"' in p][0]
head = doc0[:doc0.find('<w:body>') + len('<w:body>')]
sect = '<w:sectPr><w:pgSz w:w="11910" w:h="16840"/><w:pgMar w:top="1580" w:right="320" w:bottom="280" w:left="200" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>'
def scale(c, f):
    def sv(m):
        v = float(m.group(1)) * f
        return '<c:v>%s</c:v>' % (('%d' % round(v)) if v >= 10 else repr(round(v, 3)))
    def blk(m): return re.sub(r'<c:v>([0-9.]+)</c:v>', sv, m.group(0))
    return re.sub(r'<c:val>.*?</c:val>', blk, c, flags=re.S)
def make(tag, fmt=None, f=None, w=None, h=None):
    c = chart0; p = para
    if fmt is not None: c = c.replace(FMT, fmt)
    if f: c = scale(c, f)
    e = re.search(r'<wp:extent cx="(\d+)" cy="(\d+)"/>', p)
    cx, cy = int(e.group(1)), int(e.group(2))
    if w: cx = int(w * 12700)
    if h: cy = int(h * 12700)
    p = p.replace(e.group(0), '<wp:extent cx="%d" cy="%d"/>' % (cx, cy))
    p = re.sub(r'(<a:ext cx=")\d+(" cy=")\d+(")', lambda m: '%s%d%s%d%s' % (m.group(1), cx, m.group(2), cy, m.group(3)), p)
    p = re.sub(r'<w:ind [^>]*/>', '', p)
    d = head + p + sect
    o = zipfile.ZipFile('%s/b3l-%s.docx' % (out, tag), 'w', zipfile.ZIP_DEFLATED)
    for it in z.infolist():
        data = z.read(it.filename)
        if it.filename == 'word/charts/chart3.xml': data = c.encode('utf8')
        if it.filename == 'word/document.xml': data = d.encode('utf8')
        o.writestr(it.filename, data)
    o.close()
make('bl'); make('nf', fmt='#,##0'); make('gap', fmt='#,##0_)'); make('gen', fmt='General')
make('v1000', f=1000); make('v1e-2', f=0.01); make('v1e-4', f=0.0001)
for w in (400, 440, 480, 520, 560): make('w%d' % w, w=w)
for h in (260, 300, 340, 400): make('h%d' % h, h=h)
