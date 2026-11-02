#!/usr/bin/env python3
"""Lab ldc (for amd-opus / amd-7): in a mode-15 (2013 layout) table cell, does a line-OPENING "，" give when another
mark ("；") is on the line?  zh-8628cfbe's cell paragraph "(1)年度內…（最高加至2分），獲選財政部廉潔楷模1名加2分；合計最高加至4分。…"
(its own pPr: hanging indent 288, jc both, kinsoku 0, overflowPunct 0, 標楷體 12pt) is cut to its third sentence: a manual
line break before the ，so that the comma opens a line, as in Word's print where "合|計" is refused 9.05 over.  The cell is fixed at
its text width (209.3pt = 4186 tw, margins 28 tw) and the section is the paragraph's own.
Variants:  A "(1)…（最高加至2分）<br>，獲選財政部廉潔楷模1名加2分；合計最高加至4分。"  (as in the print)
           B the comma replaced by an ideograph 之 (same width; no line-opening mark): "<br>之獲選財政部廉潔楷模1名加2分；合計最高加至4分。"  (no line-opening mark)
           C as A with "；" replaced by "及": the opening comma is the only mark on the line (a control: amd-3's rule refuses).
The right indent steps by 4 twips (0.2pt) so that the first character past the margin, "計" (12pt), overhangs 3 -> 11pt.
START gives, per variant, the right indent at which it is 3pt over (from our own layout, run.sh), N the number of steps.
Read: for each paragraph, in order, the second line's text of the paragraph in Word's print: whether it ends with 計 (taken)
or 合 (refused).
gen.py VARIANT SRC.docx OUT.docx START_TWIPS [N]   (VARIANT A | B | C; SRC zh-8628cfbe)"""
import sys, re, zipfile
var, src, out, start = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
n = int(sys.argv[5]) if len(sys.argv) > 5 else 41
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode('utf-8')
text = lambda s: ''.join(re.findall(r'<w:t[^>]*>([^<]*)', s))
paras = list(re.finditer(r'<w:p[ >](?:(?!<w:p[ >]).)*?</w:p>', doc, flags=re.S))
para = [m.group(0) for m in paras if '加2分；合計' in text(m.group(0))][0]
m = re.match(r'(<w:p[^>]*>)(<w:pPr>.*?</w:pPr>)?(.*)</w:p>$', para, flags=re.S)
ppr = m.group(2)
rpr = '<w:rPr><w:rFonts w:eastAsia="標楷體"/></w:rPr>'
def run(t): return '<w:r>%s<w:t xml:space="preserve">%s</w:t></w:r>' % (rpr, t)
br = '<w:r>%s<w:br/></w:r>' % rpr
second = '獲選財政部廉潔楷模1名加2分；合計最高加至4分。'
if var == 'C': second = second.replace('；', '及')
head = '(1)年度內發現員工違反公務員廉政倫理規範事件（最高加至2分）'
lead = '之' if var == 'B' else '，'
body = run(head) + br + run(lead + second)
i = doc.index(para)
tb0 = doc.rindex('<w:tbl>', 0, i)
tblpr = re.search(r'<w:tblPr>.*?</w:tblPr>', doc[tb0:], flags=re.S).group(0)
tblpr = re.sub(r'<w:tblW [^>]*/>', '<w:tblW w:w="4242" w:type="dxa"/>', tblpr)
tblpr = re.sub(r'<w:tblInd [^>]*/>', '', tblpr)
tcp = '<w:tcPr><w:tcW w:w="4242" w:type="dxa"/></w:tcPr>'
out_paras = []
for k in range(n):
    right = start + 4 * k
    p = re.sub(r'<w:ind ([^>]*?)/>', lambda q: '<w:ind ' + re.sub(r'\s*w:right(Chars)?="[^"]*"', '', q.group(1)) + ' w:right="%d"/>' % right, ppr, count=1)
    one = '<w:p>%s%s</w:p>' % (p, body)
    out_paras.append('<w:tbl>%s<w:tblGrid><w:gridCol w:w="4242"/></w:tblGrid><w:tr><w:tc>%s%s</w:tc></w:tr></w:tbl><w:p/>' % (tblpr, tcp, one))
own = re.search(r'<w:sectPr[ >].*?</w:sectPr>', doc[i:], flags=re.S).group(0)
d = re.sub(r'(<w:body>).*(</w:body>)', lambda k: k.group(1) + ''.join(out_paras) + own + k.group(2), doc, count=1, flags=re.S)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zo:
    for nme in z.namelist():
        zo.writestr(nme, d.encode('utf-8') if nme == 'word/document.xml' else z.read(nme))
print(var, len(out_paras), 'paragraphs from right indent', start)
