# lab c9b (for amd-5): lo-c9b8c5abfa6d7bef's floating table (8 rows, A1..A8; A5 splits across the page foot), copied into one section per variant.
# usage: gen.py SRC_DOCX OUTDIR -> c9H (page height 580..640 step 4, 16 sections), c9Y (tblpY shifted -8..+7 pt, page 612), c9B (bottom margin 0.5..1.5in), c9F (footer distance 0..., page 612)
import sys, re, zipfile, os
src, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src); files = [(i.filename, z.read(i.filename)) for i in z.infolist() if not i.filename.endswith('/')]
doc = dict(files)['word/document.xml'].decode('utf8')
t0 = doc.index('<w:tbl>'); t1 = doc.index('</w:tbl>') + 8
tbl = doc[t0:t1]; sect = re.findall(r'<w:sectPr.*?</w:sectPr>', doc, re.S)[-1]
head = doc[:doc.index('<w:body>') + 8]
def sec(h=12240, bot=1440, foot=708):
    s = sect.replace('w:h="12240"', 'w:h="%d"' % h).replace('w:bottom="1440"', 'w:bottom="%d"' % bot).replace('w:footer="708"', 'w:footer="%d"' % foot)
    return s
def block(n, y=3286):
    t = tbl.replace('w:tblpY="3286"', 'w:tblpY="%d"' % y).replace('<w:t>A1</w:t>', '<w:t>A1 S%02d</w:t>' % n, 1)
    return t
EMPTY = '<w:p/>'
RPR = '<w:rPr><w:rFonts w:ascii="Helvetica" w:hAnsi="Helvetica" w:cs="Helvetica"/><w:lang w:val="nl-BE"/></w:rPr>'
def dt(s=''): return '<w:p><w:pPr>%s%s</w:pPr><w:r><w:t>dt</w:t></w:r></w:p>' % (RPR, s)
def make(name, secs):  # secs: (h, y, bot, foot); each section = empty paragraph, the table, the "dt" paragraph (as the source)
    body = ''
    for n, (h, y, bot, foot) in enumerate(secs, 1):
        s = sec(h, bot, foot)
        if n < len(secs): body += EMPTY + block(n, y) + dt(s.replace(' w:rsidSect="00D838DF"', ''))
        else: body += EMPTY + block(n, y) + dt() + s
    new = head + body + '</w:body></w:document>'
    with zipfile.ZipFile(os.path.join(out, name + '.docx'), 'w', zipfile.ZIP_DEFLATED) as o:
        for fn, b in files: o.writestr(fn, new.encode('utf8') if fn == 'word/document.xml' else b)
make('c9H', [(h * 20, 3286, 1440, 708) for h in range(580, 644, 4)])
make('c9Y', [(12240, 3286 + 20 * d, 1440, 708) for d in range(-8, 8)])
make('c9B', [(12240, 3286, 720 + 140 * k, 708) for k in range(12)])
make('c9F', [(12240, 3286, 1440, 20 * f) for f in (0, 10, 20, 30, 35.4, 40, 50, 60, 72, 90)])
