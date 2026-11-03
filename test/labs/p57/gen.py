#!/usr/bin/env python3
"""Lab p57 (for windows): the exact paragraph of zh-447f1d5c p57, one line + tail, right indent stepped so the available width
crosses the line's natural width (about 442.2 pt).  Does Word keep 的 on the first line?  Also a left-aligned natural-width copy.
Docs: struct 'real' (runs as in the document), 'own' (的 in its own run), 'one' (all one run).  Every doc reuses the original
styles/settings/section/footers of the document (copied from the source docx)."""
import sys, zipfile, re
SRC = sys.argv[1]; OUT = sys.argv[2]
RPR = '<w:rPr><w:rFonts w:hAnsi="Times New Roman" w:hint="eastAsia"/><w:color w:val="000000" w:themeColor="text1"/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr>'
def run(t): return '<w:r>%s<w:t xml:space="preserve">%s</w:t></w:r>' % (RPR, t)
A = '依据《固定资产分类与代码》（'; L = 'GB/T14885-2010'; B = '）标准编码'; X = '的'; T = '选项，按固定资产分类代码进行填列；无形资产依据《无形资产分类与代码》'
def runs(struct):
    if struct == 'real': return run(A) + run(L) + run(B + X + T)
    if struct == 'own':  return run(A) + run(L) + run(B) + run(X) + run(T)
    return run(A + L + B + X + T)
def para(struct, r, jc):
    return ('<w:p><w:pPr><w:pStyle w:val="2"/><w:spacing w:line="560" w:lineRule="exact"/><w:ind w:left="0" w:right="%d" w:firstLineChars="0" w:firstLine="0"/><w:jc w:val="%s"/>'
            '<w:rPr><w:rFonts w:hAnsi="Times New Roman"/><w:sz w:val="32"/></w:rPr></w:pPr>%s</w:p>') % (r, jc, runs(struct))
RS = list(range(-30, 21))
src = zipfile.ZipFile(SRC)
doc = src.read('word/document.xml').decode('utf8')
head = doc[:doc.index('<w:body>') + 8]; sect = doc[doc.rindex('<w:sectPr'):]
for struct in ('real', 'own', 'one'):
    body = ''.join(para(struct, r, 'both') for r in RS)
    # natural-width copy: left aligned, very wide right indent (-3000) so the whole line + tail stays on one line
    body += para(struct, -3000, 'left')
    new = head + body + sect
    with zipfile.ZipFile('%s/p57-%s.docx' % (OUT, struct), 'w', zipfile.ZIP_DEFLATED) as z:
        for i in src.infolist():
            z.writestr(i.filename, new.encode('utf8') if i.filename == 'word/document.xml' else src.read(i.filename))
open(OUT + '/steps.txt', 'w').write('right indent twips, paragraph order: ' + ' '.join(map(str, RS)) + ' ; last paragraph = natural-width copy (left aligned)\n')
print('ok')
