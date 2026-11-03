#!/usr/bin/env python3
"""Lab dbt (for amd-opus): what lets Word for Windows take "重" onto zh-db07d44e's p10 cell line
"(1)台電公司經營績效指標（配分權重" 1.34pt past what its "（" can give (lab dbs: from 3949
twips, refused from 3945 at 1.54; the same with no full-width mark on the line at all, row i),
when the corpus's other lines are refused 0.2 .. 1.2 past it. The two lines Word takes in
zh-db07d44e both end before a digit ("重|50％", "害|1次"); lines refused that way differ in
font size (14pt, 16pt), compatibility mode (14) or language (zh-CN). Each row as dbs's row a
(the cell, tcW stepped):
  dbt-a.docx (the document's own settings, mode 15)
    a  control: dbs row a, 3925 .. 3985 by 4
    c  "重50％" written "重五十％": no digit, no automatic space after 重; 3925 .. 3985 by 4
    l  the label "(1)" removed (13.99pt shorter): 3645 .. 3705 by 4
    n  the label "(1)" and the "50" both: "台電…權重五十％"; 3645 .. 3705 by 4
    e  the paragraph at 14pt (w:sz 28): 4543 .. 4633 by 6
    f  the paragraph at 16pt (w:sz 32): 5159 .. 5249 by 6
    m  新細明體 for 標楷體: 3925 .. 3985 by 4
  dbt-m.docx  rows a and c, compatibilityMode 14
Read: for each row, the first line's last characters (does it end at "重"); and for the first
width of each row that ends at "重", line 1's per-character x origins (as DBS-CHARS).
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
def label(p):
    q = p.replace('>(1)<', '>1.1<', 1)
    assert q != p, 'label'
    return q
def nomarks(p):
    q = p.replace('（', '第', 1).replace('）', '項', 1)
    assert q != p
    return q
def nodigit(p):
    q = p.replace('<w:t>50</w:t>', '<w:t>五十</w:t>', 1)
    assert q != p, 'digit'
    return q
def nolabel(p):
    q = re.sub(r'<w:r [^>]*>(?:(?!<w:r[ >]).)*?<w:t>\(1\)</w:t></w:r>', '', p, count=1, flags=re.S)
    assert q != p, 'label'
    return q
def size(p, hp):
    q = p.replace('<w:szCs w:val="24"/>', '<w:sz w:val="%d"/><w:szCs w:val="%d"/>' % (hp, hp))
    assert q != p, 'size'
    return q
def ming(p):
    q = p.replace('w:eastAsia="標楷體"', 'w:eastAsia="新細明體"')
    assert q != p, 'ming'
    return q
W = range(3925, 3986, 4)
WL = range(3645, 3706, 4)
rows = {
    'a': lambda: ''.join(table(w, p10) for w in W),
    'c': lambda: ''.join(table(w, nodigit(p10)) for w in W),
    'l': lambda: ''.join(table(w, nolabel(p10)) for w in WL),
    'n': lambda: ''.join(table(w, nolabel(nodigit(p10))) for w in WL),
    'e': lambda: ''.join(table(w, size(p10, 28)) for w in range(4543, 4634, 6)),
    'f': lambda: ''.join(table(w, size(p10, 32)) for w in range(5159, 5250, 6)),
    'm': lambda: ''.join(table(w, ming(p10)) for w in W),
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
write('dbt-a', ''.join(rows[k]() for k in 'aclnefm'))
m14 = settings.replace('w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"', 'w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="14"')
assert m14 != settings
write('dbt-m', rows['a']() + rows['c'](), settings_x=m14)
