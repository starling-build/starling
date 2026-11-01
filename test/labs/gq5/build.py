#!/usr/bin/env python3
"""Lab gq5: is the half-em cut of gq3/gq4 a settings effect?   usage: build.py OUTDIR [TEMPLATE.docx]
gq4 showed Word refuses the squeeze at less than half an em of room left (4.5pt for the 9pt line, 6.0 for the 12pt line) in zh-9c162f26's paragraph on its linesAndChars
charSpace -842 grid, and takes it like ours with charSpace 0 or no character grid; zh-08e95de4 (the same kind of grid, 11.8 cells for 12pt) takes characters with 1.1pt left.
The two documents' settings differ: zh-9c162f26 has w:noPunctuationKerning 1 and w:doNotUseEastAsianBreakRules (and balanceSingleByteDoubleByteWidth, useFELayout, compressPunctuation,
as zh-08e95de4 does). So the SAME paragraph (zh-9c162f26's line A in a one-cell table, jc both, the original -842 grid) is set at 9 / 10.5 / 12pt, R = 0..12pt by 1pt, in FIVE documents that differ in
settings.xml only: s0 = the original | s1 = no w:noPunctuationKerning | s2 = no w:doNotUseEastAsianBreakRules | s3 = neither | s4 = characterSpacingControl doNotCompress.
5 x 3 x 13 = 195 pages (39 per document). Per document the R where each font's count first drops is the cut; s0 should be gq4's gOrig rows (Word: f9 42 x13, f10 36 x9 then 35, f12 32 x3 then 31).
Print all five with Word for Windows, `analyze.py gq5-s0.pdf ... gq5-s4.pdf > gq5.tsv` (PyMuPDF; reads gq5-index.tsv)."""
import sys, os, re, zipfile
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
tpl = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../corpus/docx/docs/zh-9c162f2651f3787c08f4acdbf40e0f55274e6f5eea9592c05a0f4928dda0eeaf.docx')
A = '4、装饰装修期间每3日巡查1 次现场，发现业主或使用人未申报登记或者有违法违规行为的，应立即劝阻；拒不改正的，报告相关行政主管部门及业主、业主委员会。'
def marks_off(t):
    o = ''
    for i, c in enumerate(t):
        o += ('的' if c == '，' else '之') if c in '，、' and i >= 2 else c
    return o
FONTS = [('f9', 18), ('f10', 21), ('f12', 24)]
SETS = ['s0', 's1', 's2', 's3', 's4']
def rpr(sz):
    return '<w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:color w:val="000000"/><w:sz w:val="%d"/><w:szCs w:val="%d"/></w:rPr>' % (sz, sz)
def para(text, r_tw, sz):
    return ('<w:p><w:pPr><w:keepNext w:val="0"/><w:keepLines w:val="0"/><w:pageBreakBefore w:val="0"/><w:kinsoku/><w:wordWrap/><w:overflowPunct/><w:topLinePunct w:val="0"/><w:adjustRightInd/><w:snapToGrid/>'
            '<w:spacing w:line="360" w:lineRule="exact"/><w:ind w:right="%d"/><w:jc w:val="both"/>%s</w:pPr><w:r>%s<w:t xml:space="preserve">%s</w:t></w:r></w:p>') % (r_tw, rpr(sz), rpr(sz), text)
def table(inner):
    return ('<w:tbl><w:tblPr><w:tblW w:w="7647" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr>'
            '<w:tblGrid><w:gridCol w:w="7647"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="7647" w:type="dxa"/></w:tcPr>%s</w:tc></w:tr></w:tbl>') % inner
src = zipfile.ZipFile(tpl); items = [(x.filename, src.read(x.filename)) for x in src.infolist()]
doc = src.read('word/document.xml').decode('utf8'); settings = src.read('word/settings.xml').decode('utf8')
head = doc[:doc.index('<w:body>') + 8]; sect = doc[doc.rindex('<w:sectPr'):]
def tweak(st, name):
    if name in ('s1', 's3'): st, k = re.subn(r'<w:noPunctuationKerning[^>]*/>', '', st); assert k == 1, 'noPunctuationKerning'
    if name in ('s2', 's3'): st, k = re.subn(r'<w:doNotUseEastAsianBreakRules[^>]*/>', '', st); assert k == 1, 'doNotUseEastAsianBreakRules'
    if name == 's4': st, k = re.subn(r'(<w:characterSpacingControl w:val=")compressPunctuation(")', r'\1doNotCompress\2', st); assert k == 1, 'characterSpacingControl'
    return st
index = []; n = 0
for sname in SETS:
    body = ''; first = True
    for fname, sz in FONTS:
        for k in range(13):
            r = k * 20
            if not first: body += '<w:p><w:pPr><w:pageBreakBefore/><w:spacing w:line="20" w:lineRule="exact"/></w:pPr></w:p>'
            body += table(para(A, r, sz)); first = False; n += 1
            index.append((sname, '%s-%s' % (sname, fname), r, A))
    dst = os.path.join(out, 'gq5-%s.docx' % sname)
    with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as z:
        for fn, data in items:
            if fn == 'word/document.xml': data = (head + body + sect).encode('utf8')
            if fn == 'word/settings.xml': data = tweak(settings, sname).encode('utf8')
            z.writestr(fn, data)
    print(dst)
with open(os.path.join(out, 'gq5-index.tsv'), 'w') as f:
    f.write('doc\tpage\tvariant\tR_twips\ttext\n')
    pg = {}
    for d, v, r, t in index:
        pg[d] = pg.get(d, 0) + 1
        f.write('%s\t%d\t%s\t%d\t%s\n' % (d, pg[d], v, r, t))
print(n, 'pages')
