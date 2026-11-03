#!/usr/bin/env python3
"""Lab p57b: one factor off at a time from the real p57 line (struct 'real'); right indent -6..+6 twips, 13 paragraphs per doc."""
import sys, zipfile, re
SRC, OUT = sys.argv[1], sys.argv[2]
RPR = '<w:rPr><w:rFonts w:hAnsi="Times New Roman" w:hint="eastAsia"/><w:color w:val="000000" w:themeColor="text1"/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr>'
A = '依据《固定资产分类与代码》（'; L = 'GB/T14885-2010'; B = '）标准编码的选项，按固定资产分类代码进行填列；无形资产依据《无形资产分类与代码》'
RS = list(range(-6, 7))
def run(t, rpr=RPR): return '<w:r>%s<w:t xml:space="preserve">%s</w:t></w:r>' % (rpr, t)
def para(r, a=A, b=B, rpr=RPR, line='<w:spacing w:line="560" w:lineRule="exact"/>'):
    return ('<w:p><w:pPr><w:pStyle w:val="2"/>%s<w:ind w:left="0" w:right="%d" w:firstLineChars="0" w:firstLine="0"/><w:jc w:val="both"/>'
            '<w:rPr><w:rFonts w:hAnsi="Times New Roman"/><w:sz w:val="32"/></w:rPr></w:pPr>%s%s%s</w:p>') % (line, r, run(a, rpr), run(L, rpr), run(b, rpr))
src = zipfile.ZipFile(SRC)
doc = src.read('word/document.xml').decode('utf8')
head = doc[:doc.index('<w:body>') + 8]; sect = doc[doc.rindex('<w:sectPr'):]
def build(name, paras, styles=None, settings=None):
    new = head + ''.join(paras) + sect
    with zipfile.ZipFile('%s/%s.docx' % (OUT, name), 'w', zipfile.ZIP_DEFLATED) as z:
        for i in src.infolist():
            d = src.read(i.filename)
            if i.filename == 'word/document.xml': d = new.encode('utf8')
            if i.filename == 'word/styles.xml' and styles: d = styles(d.decode('utf8')).encode('utf8')
            if i.filename == 'word/settings.xml' and settings: d = settings(d.decode('utf8')).encode('utf8')
            z.writestr(i.filename, d)
# base: control
build('b0-control', [para(r) for r in RS])
# song: 宋体 everywhere (styles + runs)
song = RPR.replace('<w:rFonts w:hAnsi="Times New Roman" w:hint="eastAsia"/>', '<w:rFonts w:ascii="宋体" w:eastAsia="宋体" w:hAnsi="宋体" w:hint="eastAsia"/>')
build('b1-songti', [para(r, rpr=song) for r in RS], styles=lambda s: s.replace('仿宋_GB2312', '宋体'))
# compat flags off
def nocompat(s):
    for f in ('doNotWrapTextWithPunct', 'doNotUseEastAsianBreakRules', 'useAltKinsokuLineBreakRules'): s = s.replace('<w:%s/>' % f, '')
    return s
build('b2-nocompat', [para(r) for r in RS], settings=nocompat)
# no brackets: replace 《》（） by ideographs
nb = lambda t: t.replace('《', '名').replace('》', '称').replace('（', '号').replace('）', '码')
build('b3-nobrackets', [para(r, a=nb(A), b=nb(B)) for r in RS])
# auto line spacing instead of exact 560
build('b4-autoline', [para(r, line='<w:spacing w:line="240" w:lineRule="auto"/>') for r in RS])
open(OUT + '/steps2.txt', 'w').write('right indent twips per paragraph: ' + ' '.join(map(str, RS)) + '\n')
