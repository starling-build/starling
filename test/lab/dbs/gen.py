#!/usr/bin/env python3
"""Lab dbs (for amd-opus): what separates zh-db07d44e's p10 cell line from the ~190 corpus
lines Word refuses at the same overrun. Word for Windows takes "重" onto
"(1)台電公司經營績效指標（配分權重…" from a 3949-twip cell (lab dbc), squeezing the "（"
6.12 and the ideographs 0.12 each; ours from 3977. Mode 15, compressPunctuation, 標楷體/
Times 12, jc both, ind left 240 hanging 240, the cell's tcMar left 108 only, docGrid lines.
Every variant: the paragraph, width stepped 3925 .. 3985 twips by 4 (16 rows).
  dbs-a.docx (the document's settings)
    a  cell as in dbc-a (control)
    b  BODY: no table; right indent so the text is (w - 216) twips wide, as the cell's
    e  cell, tblLayout fixed
    f  cell, tcMar left 108 AND right 108 stated
    g  cell, no tcMar (the table's defaults)
    h  cell, label "(1)" written "1.1" (no ASCII brackets on the line, about as wide)
    i  cell, the line's "（" and "）" written "第" and "項" (no full-width marks on the line);
       its widths 4045 .. 4105, the line 6pt longer
  dbs-c.docx  as dbs-a's rows a and b, characterSpacingControl doNotCompress
  dbs-d.docx  as dbs-a's rows a and b, docGrid removed
Read: for each row, the first line's last characters (does it end at "重").
usage: gen.py CORPUS_DOCX_DIR OUTDIR"""
import sys, re, zipfile, os, glob
src_dir, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
text = lambda s: ''.join(re.findall(r'<w:t[^>]*>([^<]*)', s))
z = zipfile.ZipFile(glob.glob(os.path.join(src_dir, 'zh-db07d44e*.docx'))[0])
doc = z.read('word/document.xml').decode('utf-8')
settings = z.read('word/settings.xml').decode('utf-8')
ps = [m.group(0) for m in re.finditer(r'<w:p[ >](?:(?!<w:p[ >]).)*?</w:p>', doc, flags=re.S)]
p10 = [p for p in ps if text(p).startswith('(1)台電公司經營績效指標')][0]
i = doc.find('台電公司經營績效指標'); tbl = doc.rfind('<w:tbl>', 0, i)
tblpr = re.search(r'<w:tblPr>.*?</w:tblPr>', doc[tbl:], flags=re.S).group(0)
tc = doc.rfind('<w:tc>', 0, i)
tcpr0 = re.search(r'<w:tcPr>.*?</w:tcPr>', doc[tc:], flags=re.S).group(0)
TEXT_W = 11906 - 1134 - 1134
GAP = '<w:p><w:pPr><w:spacing w:after="0" w:line="120" w:lineRule="exact"/></w:pPr></w:p>'
def table(w, p, layout='', tcmar='keep'):
    tp = re.sub(r'<w:tblW [^>]*/>', '<w:tblW w:w="%d" w:type="dxa"/>' % w, tblpr)
    if layout: tp = tp.replace('</w:tblPr>', layout + '</w:tblPr>')
    tcp = re.sub(r'<w:tcW [^>]*/>', '<w:tcW w:w="%d" w:type="dxa"/>' % w, tcpr0)
    if tcmar == 'both': tcp = tcp.replace('<w:tcMar><w:left w:w="108" w:type="dxa"/></w:tcMar>', '<w:tcMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tcMar>')
    if tcmar == 'none': tcp = re.sub(r'<w:tcMar>.*?</w:tcMar>', '', tcp)
    assert tcmar == 'keep' or tcp != re.sub(r'<w:tcW [^>]*/>', '<w:tcW w:w="%d" w:type="dxa"/>' % w, tcpr0)
    return '<w:tbl>%s<w:tblGrid><w:gridCol w:w="%d"/></w:tblGrid><w:tr><w:tc>%s%s</w:tc></w:tr></w:tbl>%s' % (tp, w, tcp, p, GAP)
def body(w, p):
    right = TEXT_W - (w - 216)
    q = p.replace('<w:ind w:left="240" w:hanging="240"/>', '<w:ind w:left="240" w:right="%d" w:hanging="240"/>' % right)
    assert q != p
    return q + GAP
def label(p):
    q = p.replace('>(1)<', '>1.1<', 1)
    assert q != p, 'label'
    return q
def nomarks(p):
    q = p.replace('（', '第', 1).replace('）', '項', 1)
    assert q != p
    return q
W = range(3925, 3986, 4)
rows = {
    'a': lambda: ''.join(table(w, p10) for w in W),
    'b': lambda: ''.join(body(w, p10) for w in W),
    'e': lambda: ''.join(table(w, p10, layout='<w:tblLayout w:type="fixed"/>') for w in W),
    'f': lambda: ''.join(table(w, p10, tcmar='both') for w in W),
    'g': lambda: ''.join(table(w, p10, tcmar='none') for w in W),
    'h': lambda: ''.join(table(w, label(p10)) for w in W),
    'i': lambda: ''.join(table(w, nomarks(p10)) for w in range(4045, 4106, 4)),
}
def write(name, body_xml, doc_x=doc, settings_x=settings):
    own = re.search(r'<w:sectPr[ >](?:(?!<w:sectPr[ >]).)*?</w:sectPr>\s*</w:body>', doc_x, flags=re.S).group(0)
    own = re.sub(r'<w:(headerReference|footerReference)[^>]*/>', '', own)
    out = re.sub(r'(<w:body>).*(</w:body>)', lambda k: k.group(1) + body_xml + own, doc_x, count=1, flags=re.S)
    with zipfile.ZipFile(os.path.join(outdir, name + '.docx'), 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in z.namelist():
            data = out if n == 'word/document.xml' else settings_x if n == 'word/settings.xml' else z.read(n)
            zo.writestr(n, data.encode('utf-8') if isinstance(data, str) else data)
    print(name)
write('dbs-a', ''.join(rows[k]() for k in 'abefghi'))
nc = settings.replace('w:val="compressPunctuation"', 'w:val="doNotCompress"'); assert nc != settings
write('dbs-c', rows['a']() + rows['b'](), settings_x=nc)
ng = re.sub(r'<w:docGrid [^>]*/>', '', doc); assert ng != doc
write('dbs-d', rows['a']() + rows['b'](), doc_x=ng)
