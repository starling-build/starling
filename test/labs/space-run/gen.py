# Lab: right-aligned runs of nbsp / space before CJK, as in zh-8415d258 p1.
# Paragraph = pattern x count of leading whitespace chars + 水利部办公厅.
# Template: the real docx (styles, sectPr, fonts); only the body is replaced.
import zipfile, re, sys, glob
src = glob.glob('test/corpus/docx/docs/zh-8415d258*.docx')[0]
out = sys.argv[1] if len(sys.argv) > 1 else 'test/labs/space-run/space-run.docx'
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode()
m = re.search(r'<w:p [^>]*>(?:(?!</w:p>).)*水利部办公厅</w:t></w:r></w:p>', doc, re.S)
tpl = m.group(0)
sect = re.search(r'<w:sectPr.*?</w:sectPr>', doc, re.S).group(0)
head = doc[:doc.index('<w:body>') + 8]
N, S = ' ', ' '
pats = {
  'altN': lambda n: ''.join(N if i % 2 == 0 else S for i in range(n)),   # real: nbsp first
  'altS': lambda n: ''.join(S if i % 2 == 0 else N for i in range(n)),
  'sp':   lambda n: S * n,
  'nb':   lambda n: N * n,
}
counts = list(range(50, 61)) + list(range(105, 116)) + list(range(150, 161))
paras = []
for name, f in pats.items():
    for n in counts:
        label = '%s%d' % (name, n)
        p = tpl.replace(re.search(r'<w:t>[^<]*水利部办公厅</w:t>', tpl).group(0),
                        '<w:t xml:space="preserve">%s水利部办公厅</w:t>' % f(n))
        lab = '<w:p><w:pPr><w:jc w:val="left"/></w:pPr><w:r><w:t>%s</w:t></w:r></w:p>' % label
        paras.append(lab + p)
body = ''.join(paras)
new = head + body + sect + '</w:body></w:document>'
zo = zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED)
for it in z.infolist():
    zo.writestr(it, new.encode() if it.filename == 'word/document.xml' else z.read(it.filename))
zo.close(); print(out, len(paras))
