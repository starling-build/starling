#!/usr/bin/env python3
"""Lab dbc (for amd-opus): two zh-db07d44e cell lines Word for Windows fits and ours breaks one character early.
Mode 15, compressPunctuation, 標楷體/Times 12, jc both, hanging indent with an ASCII "(n)" label.
  p10 "(1)台電公司經營績效指標（配分權重…" (cell 3965 twips): Word takes "重", by our sums 0.54pt past what the
      "（" gives (6.0); its print squeezes the "（" 6.12 and sets the next ideographs 11.88 apart.
  p11 "(4)通霄新3機107年12月15日…" (cell 2903): Word takes "月" 5.64pt over, its six automatic spaces (3.0) set
      at 2.04; ours caps what they give at a quarter em (3.0), which ~100 corpus lines bear out.
Question: how far over does Word take each, and does the label matter? Each paragraph alone in a one-cell table
(the document's table properties), the cell width stepped:
  p10  3925 .. 3985 twips by 4 (16 tables)       p11  2783 .. 2923 by 10 (15 tables)
  dbc-a  as the document     dbc-b  the "(n)" label run removed     dbc-c  jc left
Each document starts with both paragraphs at the document's widths (control).
gen.py CORPUS_DOCX_DIR OUTDIR"""
import sys, re, zipfile, os, glob
src_dir, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
text = lambda s: ''.join(re.findall(r'<w:t[^>]*>([^<]*)', s))
z = zipfile.ZipFile(glob.glob(os.path.join(src_dir, 'zh-db07d44e*.docx'))[0])
doc = z.read('word/document.xml').decode('utf-8')
ps = [m.group(0) for m in re.finditer(r'<w:p[ >](?:(?!<w:p[ >]).)*?</w:p>', doc, flags=re.S)]
p10 = [p for p in ps if text(p).startswith('(1)台電公司經營績效指標')][0]
p11 = [p for p in ps if text(p).startswith('(4)通霄新3機')][0]
i = doc.find('台電公司經營績效指標'); tbl = doc.rfind('<w:tbl>', 0, i)
tblpr = re.search(r'<w:tblPr>.*?</w:tblPr>', doc[tbl:], flags=re.S).group(0)
tcpr = lambda w: '<w:tcPr><w:tcW w:w="%d" w:type="dxa"/></w:tcPr>' % w
def table(w, p):
    return ('<w:tbl>%s<w:tblGrid><w:gridCol w:w="%d"/></w:tblGrid><w:tr><w:tc>%s%s</w:tc></w:tr></w:tbl>'
            '<w:p><w:pPr><w:spacing w:after="0" w:line="120" w:lineRule="exact"/></w:pPr></w:p>') % (
            re.sub(r'<w:tblW [^>]*/>', '<w:tblW w:w="%d" w:type="dxa"/>' % w, tblpr), w, tcpr(w), p)
def nolabel(p):
    rs = re.findall(r'<w:r[ >](?:(?!<w:r[ >]).)*?</w:r>', p, flags=re.S)
    return p.replace(rs[0], '', 1) if re.fullmatch(r'\(\d\)', text(rs[0])) else p
def left(p): return p.replace('<w:jc w:val="both"/>', '<w:jc w:val="left"/>')
def write(body, name):
    own = re.search(r'<w:sectPr[ >](?:(?!<w:sectPr[ >]).)*?</w:sectPr>\s*</w:body>', doc, flags=re.S).group(0)
    own = re.sub(r'<w:(headerReference|footerReference)[^>]*/>', '', own)
    out = re.sub(r'(<w:body>).*(</w:body>)', lambda k: k.group(1) + body + own, doc, count=1, flags=re.S)
    path = os.path.join(outdir, name + '.docx')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in z.namelist():
            zo.writestr(n, out.encode('utf-8') if n == 'word/document.xml' else z.read(n))
    print(name, '->', path)
ctl = table(3965, p10) + table(2903, p11)
for name, f in (('dbc-a', lambda p: p), ('dbc-b', nolabel), ('dbc-c', left)):
    write(ctl + ''.join(table(w, f(p10)) for w in range(3925, 3986, 4)) + ''.join(table(w, f(p11)) for w in range(2783, 2924, 10)), name)
