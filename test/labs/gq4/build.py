#!/usr/bin/env python3
"""Lab gq4: what sets the cut at which Word refuses a squeeze?   usage: build.py OUTDIR [TEMPLATE.docx]
gq3 (zh-9c162f26's real line A, 9pt, linesAndChars charSpace -842, one cell 371.55pt, jc both, right indent R stepped) showed Word takes the 44th character
squeezing the line's 3 marks while 4.58pt of room is left and refuses it at 4.49 (= half the 9pt em); ours had no such cut -- but the cut is not general: other
documents' Word prints take characters with less room (zh-d8247da5: 10pt, letter spacing -1pt, 'lines' grid, 4.95 left; zh-08e95de4: 1.1 left).
So the SAME paragraph is set here with three things varied and crossed: FONT 9 / 10.5 / 12pt; GRID linesAndChars charSpace -842 (the original) / linesAndChars charSpace 0 /
'lines' (no character grid); MARKS the original (three on line 1) / none (every '，、' after the first two characters an ideograph).  R = 0..12pt by 1pt.
18 configurations x 13 = 234 pages in THREE documents (the grid is the section's, so one document per grid): gq4-gOrig.docx, gq4-gCS0.docx, gq4-gLines.docx (78 pages each).
Per configuration the R at which line 1 loses a character is the cut; compare Word's with ours (GQ4-OURS.tsv).
Print all three with Word for Windows, then `analyze.py gq4-gOrig.pdf gq4-gCS0.pdf gq4-gLines.pdf > gq4.tsv` (PyMuPDF; reads gq4-index.tsv)."""
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
GRIDS = [('gOrig', None), ('gCS0', '<w:docGrid w:type="linesAndChars" w:linePitch="%s" w:charSpace="0"/>'), ('gLines', '<w:docGrid w:type="lines" w:linePitch="%s"/>')]
TEXTS = [('m3', A), ('m0', A[:2] + marks_off(A[2:]))]
def rpr(sz):
    return '<w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:color w:val="000000"/><w:sz w:val="%d"/><w:szCs w:val="%d"/></w:rPr>' % (sz, sz)
def para(text, r_tw, sz):
    return ('<w:p><w:pPr><w:keepNext w:val="0"/><w:keepLines w:val="0"/><w:pageBreakBefore w:val="0"/><w:kinsoku/><w:wordWrap/><w:overflowPunct/><w:topLinePunct w:val="0"/><w:adjustRightInd/><w:snapToGrid/>'
            '<w:spacing w:line="360" w:lineRule="exact"/><w:ind w:right="%d"/><w:jc w:val="both"/>%s</w:pPr><w:r>%s<w:t xml:space="preserve">%s</w:t></w:r></w:p>') % (r_tw, rpr(sz), rpr(sz), text)
def table(inner):
    return ('<w:tbl><w:tblPr><w:tblW w:w="7647" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr>'
            '<w:tblGrid><w:gridCol w:w="7647"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="7647" w:type="dxa"/></w:tcPr>%s</w:tc></w:tr></w:tbl>') % inner
src = zipfile.ZipFile(tpl); items = [(i.filename, src.read(i.filename)) for i in src.infolist()]; doc = src.read('word/document.xml').decode('utf8')
head = doc[:doc.index('<w:body>') + 8]; sect = doc[doc.rindex('<w:sectPr'):]
m = re.search(r'<w:docGrid[^>]*w:linePitch="(\d+)"[^>]*/>', sect); assert m, 'no docGrid in the template'
index = []; n = 0
for gname, g in GRIDS:
    sect_v = sect if g is None else sect.replace(m.group(0), g % m.group(1))
    body = ''; first = True
    for fname, sz in FONTS:
        for tname, text in TEXTS:
            for k in range(13):
                r = k * 20
                if not first: body += '<w:p><w:pPr><w:pageBreakBefore/><w:spacing w:line="20" w:lineRule="exact"/></w:pPr></w:p>'
                body += table(para(text, r, sz)); first = False; n += 1
                index.append((gname, '%s-%s-%s' % (fname, gname, tname), r, text))
    dst = os.path.join(out, 'gq4-%s.docx' % gname)
    with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as z:
        for fn, data in items:
            if fn == 'word/document.xml': data = (head + body + sect_v).encode('utf8')
            z.writestr(fn, data)
    print(dst)
with open(os.path.join(out, 'gq4-index.tsv'), 'w') as f:
    f.write('doc\tvariant\tR_twips\ttext\n')
    pg = {}
    for d, v, r, t in index:
        pg[d] = pg.get(d, 0) + 1
        f.write('%s\t%d\t%s\t%d\t%s\n' % (d, pg[d], v, r, t))
print(n, 'pages')
