# Lab: zh-e0ca7252 p46. Word breaks "…與週邊設|備，並僅開放…" (comma carried with 備) where we
# hang the comma past the edge. The real paragraph (styles, numbering, 12 pt 標楷體, jc both,
# compressPunctuation) is repeated with the RIGHT INDENT stepped 0..14 pt in 0.5 pt steps, so
# the mark lands at every distance from the edge; plus variants of the same text:
#   A  as is ("，")      B  "，" -> "。"      C  "，" -> "、"      D  overflowPunct off (as is)
# A label paragraph (left aligned) precedes each case.
import zipfile, re, sys, glob
src = glob.glob('test/corpus/docx/docs/zh-e0ca7252*.docx')[0]
out = sys.argv[1] if len(sys.argv) > 1 else 'test/labs/comma-hang/comma-hang.docx'
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode()
i = doc.index('與週邊設備')
s = doc.rfind('<w:p ', 0, i); e = doc.index('</w:p>', i) + 6
tpl = doc[s:e]
sect = re.findall(r'<w:sectPr.*?</w:sectPr>', doc, re.S)[-1]
head = doc[:doc.index('<w:body>') + 8]
paras = []
for var in 'ABCD':
    for k in range(0, 29):
        r = k * 10  # twentieths of a point: 0.5 pt = 10
        p = tpl.replace('w:right="0"', 'w:right="%d"' % r)
        if var == 'B': p = p.replace('設備，', '設備。')
        if var == 'C': p = p.replace('設備，', '設備、')
        if var == 'D': p = p.replace('<w:suppressAutoHyphens/>', '<w:suppressAutoHyphens/><w:overflowPunct w:val="0"/>', 1)
        lab = '<w:p><w:pPr><w:jc w:val="left"/></w:pPr><w:r><w:t>%s r%.1f</w:t></w:r></w:p>' % (var, r / 20)
        paras.append(lab + p)
new = head + ''.join(paras) + sect + '</w:body></w:document>'
zo = zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED)
for it in z.infolist():
    zo.writestr(it, new.encode() if it.filename == 'word/document.xml' else z.read(it.filename))
zo.close(); print(out, len(paras))
