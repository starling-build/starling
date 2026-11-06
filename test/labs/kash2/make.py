#!/usr/bin/env python3
"""kash2: the real RTL low-kashida paragraph of lo-af36644e, at 33 widths (the end indent 0..16pt in 0.5pt steps), each
once as lowKashida and once as both, so Word's break of its 3rd line can be read against the line width.
Usage: make.py <lo-af36644e14e94c0e.docx> <out.docx>"""
import re, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode('utf8')
body = doc.split('<w:body>')[1]
ps = re.findall(r'<w:p[ >].*?</w:p>', body, flags=re.S)
tmpl = ps[12]
assert 'lowKashida' in tmpl
sect = re.search(r'<w:sectPr.*?</w:sectPr>', body, re.S).group(0)
def label(t):
    return ('<w:p><w:pPr><w:spacing w:before="120" w:after="0"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/>'
            '<w:sz w:val="16"/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r></w:p>' % t)
def variant(jc, tw):
    p = tmpl.replace('w:val="lowKashida"', 'w:val="%s"' % jc)
    ind = '<w:ind w:left="%d"/>' % tw
    if '<w:ind ' in p:
        p = re.sub(r'<w:ind [^>]*/>', ind, p)
    else:
        p = p.replace('<w:jc ', ind + '<w:jc ', 1)
    return p
out_ps = []
for tw in range(0, 321, 10):          # 0..16 pt in 0.5 pt
    for jc, name in (('lowKashida', 'low'), ('both', 'both')):
        out_ps.append(label('%s end-indent %.1f pt' % (name, tw / 20)))
        out_ps.append(variant(jc, tw))
newbody = ''.join(out_ps) + sect
newdoc = doc.split('<w:body>')[0] + '<w:body>' + newbody + '</w:body>' + doc.split('</w:body>')[1]
zo = zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED)
for i in z.infolist():
    zo.writestr(i, newdoc.encode('utf8') if i.filename == 'word/document.xml' else z.read(i.filename))
zo.close()
