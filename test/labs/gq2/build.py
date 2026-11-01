#!/usr/bin/env python3
"""Lab gq2: when does Word for Windows squeeze a line's marks to take one more character, on a character grid?   usage: build.py OUTDIR [TEMPLATE.docx]
Template: zh-9c162f26 (mode 14, compressPunctuation, doNotWrapTextWithPunct + doNotUseEastAsianBreakRules + balanceSingleByteDoubleByteWidth, docGrid
linesAndChars linePitch 579 charSpace -842, 9pt, justified).  In its print Word keeps the line  '4、装饰装修期间每3日巡查1 次现场，发现…的，' at 44
characters and does NOT squeeze its three marks (4.31pt in all) to take the 45th ('应'); ours does, and the same happens in ~16 lines.
Elsewhere in the document Word takes characters up to 11pt over with the same marks.  What differs is the digits and their automatic spaces?
One document, one page per test.  Each page: ONE justified paragraph, 9pt, 42 grid cells of the line + a 43rd cell (the candidate) + a 14-ideograph tail
so the paragraph wraps.  A cell is an ideograph, or (D digit groups) a single digit '3' standing where an ideograph would, or (M marks) a '，' standing
where one would.  The right indent R grows 0..8pt in 0.5pt steps (w:ind w:right in twips, 20 per step = 1pt): the line's room shrinks by R, so the squeeze
the candidate needs grows by R.  The page's FIRST LINE holds 43 characters when Word takes the candidate and 42 when it does not; the R (beyond the 70.7pt body indent that makes the body 371.55pt wide, as in the cell) at which that
flips is how much squeeze Word accepts for that mix.  Families: 'b' the paragraph in the body, 'c' the same in a one-cell table (cell text width 371.55pt =
the column of the digits' lines in zh-9c162f26).  Variants (D digit groups, M commas):  D0M2 D0M5 D1M2 D1M5 D2M2 D2M5 D4M2 D4M5.
analyze.py WORD.pdf > gq.tsv  prints, per variant and family, the last R taken and the first R refused."""
import sys, os, zipfile, random
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
tpl = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../corpus/docx/docs/zh-9c162f2651f3787c08f4acdbf40e0f55274e6f5eea9592c05a0f4928dda0eeaf.docx')
POOL = '装饰修期间每日巡查现场发业主或使用人未申报登记者有违法规行为的立即劝阻拒不改正告知相关管理部门委员会'
VARIANTS = [(0, 2, 0), (0, 2, 1), (0, 2, 2), (0, 2, 3), (0, 0, 1), (0, 0, 2), (2, 2, 1), (2, 2, 2)]   # (digit groups, marks, 'digit+blank' groups)
def cells(d, m, sp=0):
    n = 43
    marks = {int(round(n * (i + 1) / (m + 1))) - 1 for i in range(m)}
    marks = {k for k in marks if 1 <= k <= n - 4}
    digits = {int(round(n * (i + 0.5) / d)) for i in range(d)} if d else set()
    digits = {k for k in digits if k not in marks and k - 1 not in marks and k + 1 not in marks and 2 <= k <= n - 4}
    spaced = {int(round(n * (i + 0.4) / sp)) for i in range(sp)} if sp else set()
    spaced = {k for k in spaced if k not in marks and k not in digits and k - 1 not in marks and k + 1 not in marks and 2 <= k <= n - 4}
    rng = random.Random(7); out = []
    for k in range(n):
        out.append('，' if k in marks else '3' if k in digits else '1 ' if k in spaced else POOL[(k * 7 + 3) % len(POOL)])
    tail = ''.join(POOL[(k * 5 + 11) % len(POOL)] for k in range(14))
    return ''.join(out) + tail, len(marks), len(digits) + 10 * len(spaced)
RPR = '<w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:color w:val="000000"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr>'
def para(text, r_tw, brk):
    return ('<w:p><w:pPr>%s<w:kinsoku/><w:wordWrap/><w:overflowPunct/><w:adjustRightInd/><w:snapToGrid/><w:spacing w:line="360" w:lineRule="exact"/>'
            '<w:ind w:right="%d"/><w:jc w:val="both"/>%s</w:pPr><w:r>%s<w:t>%s</w:t></w:r></w:p>') % ('<w:pageBreakBefore/>' if brk else '', r_tw, RPR, RPR, text)
def cell_table(inner, brk):
    # a 1x1 table, 7647 twips wide (cell text 7431 twips = 371.55pt with the default 108 margins), first paragraph carries the page break
    return ('<w:tbl><w:tblPr><w:tblW w:w="7647" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr>'
            '<w:tblGrid><w:gridCol w:w="7647"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="7647" w:type="dxa"/></w:tcPr>%s</w:tc></w:tr></w:tbl><w:p><w:pPr><w:spacing w:line="20" w:lineRule="exact"/></w:pPr></w:p>') % inner
src = zipfile.ZipFile(tpl); doc = src.read('word/document.xml').decode('utf8')
head = doc[:doc.index('<w:body>') + 8]; sect = doc[doc.rindex('<w:sectPr'):]
body = ''; index = []; first = True
for fam in ('b', 'c'):
    for d, m, sp in VARIANTS:
        text, nm, nd = cells(d, m, sp)
        for k in range(21):
            r = k * 20
            if fam == 'b': body += para(text, r + 1414, not first)   # body text width 442.25pt less 70.7pt = the cell family's 371.55
            else:
                p = para(text, r, False)
                if not first: body += '<w:p><w:pPr><w:pageBreakBefore/><w:spacing w:line="20" w:lineRule="exact"/></w:pPr></w:p>'
                body += cell_table(p, False)
            index.append((fam, 'D%dM%dS%d' % (d, m, sp), r, nd, nm, text)); first = False
dst = os.path.join(out, 'gq2.docx')
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as z:
    for item in src.infolist():
        data = src.read(item.filename)
        if item.filename == 'word/document.xml': data = (head + body + sect).encode('utf8')
        z.writestr(item, data)
open(os.path.join(out, 'gq2-index.tsv'), 'w').write('page\tfamily\tvariant\tR_twips\tdigits\tmarks\ttext\n' + ''.join('%d\t%s\t%s\t%d\t%d\t%d\t%s\n' % ((i + 1,) + t) for i, t in enumerate(index)))
print(dst, len(index), 'pages')
