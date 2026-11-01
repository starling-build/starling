#!/usr/bin/env python3
"""Lab gq3: which element of zh-9c162f26's real lines makes Word refuse a squeeze it ought to accept?   usage: build.py OUTDIR [TEMPLATE.docx]
gq and gq2 (synthetic lines: digits, real blanks, marks, body and cell) printed IDENTICAL to ours in Word for Windows. zh-9c162f26's real line
 A = '4、装饰装修期间每3日巡查1 次现场，发现业主或使用人未申报登记或者有违法违规行为的，应立即劝阻；拒不改正的，报告相关行政主管部门及业主、业主委员会。'
ends at 44 characters ('…行为的，' -- the 45th, '应', goes down) where ours squeezes the three marks 4.31pt in all and takes it.  Here the REAL paragraph is set in the one-cell table
(371.55pt) with the right indent 0..8pt by 1pt, and the same text with ONE element changed per variant; the count of characters on line 1 at R=0 (Word 44 for orig)
and the R of the first drop say which element Word minds.  Variants: orig | no4 (no '4、') | si ('四、' for '4、') | nod ('每日', '一次': no digit at all) | d3 (only the '3' gone)
| d1 (only the '1 ' gone) | nosp ('1次': no real blank) | nomark (every '，、' an ideograph) | m1 (only the first '、' gone) | jl (left aligned) | B: the '每日' paragraph
(Word 45 on line 1, ours 46) orig and no4.  analyze.py gq3.pdf > gq3.tsv (reads gq3-index.tsv)."""
import sys, os, zipfile
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
tpl = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../corpus/docx/docs/zh-9c162f2651f3787c08f4acdbf40e0f55274e6f5eea9592c05a0f4928dda0eeaf.docx')
A = '4、装饰装修期间每3日巡查1 次现场，发现业主或使用人未申报登记或者有违法违规行为的，应立即劝阻；拒不改正的，报告相关行政主管部门及业主、业主委员会。'
B = '4、装饰装修期间每日巡查1 次现场，发现业主或使用人未申报登记或者有违法违规行为的，应立即劝阻；拒不改正的，报告相关行政主管部门及业主、业主委员会。'
def marks_off(t, keep=()):
    o = ''
    for i, c in enumerate(t):
        o += ('的' if c == '，' else '之') if c in '，、' and i not in keep else c
    return o
V = [('A-orig', A, 'both'), ('A-no4', A[2:], 'both'), ('A-si', '四' + A[1:], 'both'), ('A-nod', A.replace('每3日', '每日').replace('1 次', '一次'), 'both'),
     ('A-d3', A.replace('每3日', '每日'), 'both'), ('A-d1', A.replace('1 次', '一次'), 'both'), ('A-nosp', A.replace('1 次', '1次'), 'both'),
     ('A-nomark', A[:2] + marks_off(A[2:]), 'both'), ('A-m1', A[0] + '之' + A[2:], 'both'), ('A-jl', A, 'left'), ('B-orig', B, 'both'), ('B-no4', B[2:], 'both')]
RPR = '<w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:color w:val="000000"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr>'
def para(text, r_tw, jc):
    return ('<w:p><w:pPr><w:keepNext w:val="0"/><w:keepLines w:val="0"/><w:pageBreakBefore w:val="0"/><w:kinsoku/><w:wordWrap/><w:overflowPunct/><w:topLinePunct w:val="0"/><w:adjustRightInd/><w:snapToGrid/>'
            '<w:spacing w:line="360" w:lineRule="exact"/><w:ind w:right="%d"/><w:jc w:val="%s"/>%s</w:pPr><w:r>%s<w:t xml:space="preserve">%s</w:t></w:r></w:p>') % (r_tw, jc, RPR, RPR, text)
def table(inner):
    return ('<w:tbl><w:tblPr><w:tblW w:w="7647" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr>'
            '<w:tblGrid><w:gridCol w:w="7647"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="7647" w:type="dxa"/></w:tcPr>%s</w:tc></w:tr></w:tbl>') % inner
src = zipfile.ZipFile(tpl); doc = src.read('word/document.xml').decode('utf8')
head = doc[:doc.index('<w:body>') + 8]; sect = doc[doc.rindex('<w:sectPr'):]
body = ''; index = []; first = True
for name, text, jc in V:
    for k in range(9):
        r = k * 20
        if not first: body += '<w:p><w:pPr><w:pageBreakBefore/><w:spacing w:line="20" w:lineRule="exact"/></w:pPr></w:p>'
        body += table(para(text, r, jc)); index.append((name, r, text)); first = False
dst = os.path.join(out, 'gq3.docx')
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as z:
    for item in src.infolist():
        data = src.read(item.filename)
        if item.filename == 'word/document.xml': data = (head + body + sect).encode('utf8')
        z.writestr(item, data)
open(os.path.join(out, 'gq3-index.tsv'), 'w').write('page\tvariant\tR_twips\ttext\n' + ''.join('%d\t%s\t%d\t%s\n' % ((i + 1,) + t) for i, t in enumerate(index)))
print(dst, len(index), 'pages')
