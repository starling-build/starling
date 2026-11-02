"""anchor lab (for amd-4): rows19_c15 with visible text in the empties E1.. and trailing Z1..  usage: mk.py OUT (cwd lab/anchor)"""
import zipfile, os, sys, re
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile('orig.docx')
f = {n: z.read(n) for n in z.namelist()}
d = f['word/document.xml'].decode('utf-8')
rows = list(re.finditer(r'<w:tr[ >].*?</w:tr>', d, re.S))
assert len(rows) == 25
t1_end = d.index('</w:tbl>') + len('</w:tbl>')
t2_start = d.index('<w:tbl>', t1_end)
t2_end = d.index('</w:tbl>', t2_start) + len('</w:tbl>')
assert re.fullmatch(r'\s*<w:p><w:pPr></w:pPr></w:p><w:p><w:pPr></w:pPr></w:p>\s*', d[t1_end:t2_start])
tail = d[t2_end:]
tp = re.search(r'<w:p [^>]*/>', tail)
assert tp
before, after = tail[:tp.start()], tail[tp.end():]


def P(t):
    return '<w:p><w:pPr></w:pPr><w:r><w:t>%s</w:t></w:r></w:p>' % t


def build(name, nempty, ntrail, nrows=19):
    t1 = d[:t1_end]
    if nrows == 18:
        r = rows[18]
        t1 = t1[:r.start()].rstrip() + '\n' + t1[r.end():].lstrip()
        t1 = t1[:r.start()] + t1[r.start():]  # row 18 gone
    elif nrows == 20:
        r = rows[18]
        t1 = t1[:r.end()] + r.group(0).replace('<w:t>18</w:t>', '<w:t>19</w:t>') + t1[r.end():]
    s = t1 + ''.join(P('E%d' % (i + 1)) for i in range(nempty)) + d[t2_start:t2_end] + before + ''.join(P('Z%d' % (i + 1)) for i in range(ntrail)) + after
    g = dict(f)
    g['word/document.xml'] = s.encode('utf-8')
    with zipfile.ZipFile(os.path.join(out, name + '.docx'), 'w', zipfile.ZIP_DEFLATED) as o:
        for k, v in g.items():
            o.writestr(k, v)


build('an_a', 1, 1)
build('an_b', 2, 1)
build('an_c', 3, 1)
build('an_d', 2, 2)
build('an_b18', 2, 1, 18)
build('an_b20', 2, 1, 20)
print('ok')
