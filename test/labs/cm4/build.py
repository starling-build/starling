#!/usr/bin/env python3
"""build.py -> cm4.docx: a vertically centred cell merged over THREE rows whose page foot falls at/in a row (amd-3, for zh-5450d509 p6, zh-785e46f8)."""
import zipfile, sys
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
P = '<w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:t>%s</w:t></w:r></w:p>'
LINE = 14.65
def paras(name, n): return ''.join(P % ('%s-%d' % (name, i + 1)) for i in range(n))
def cell(w, body, vm=None):
    v = '' if vm is None else ('<w:vMerge w:val="restart"/>' if vm == 'r' else '<w:vMerge/>')
    return '<w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/>%s<w:vAlign w:val="center"/></w:tcPr>%s</w:tc>' % (w, v, body)
def row(cells, exact=None):
    h = '' if exact is None else '<w:trPr><w:trHeight w:val="%d" w:hRule="atLeast"/></w:trPr>' % round(exact * 20)
    return '<w:tr>%s%s</w:tr>' % (h, ''.join(cells))
WA, WB, WC = 1400, 1600, 4000
def table(tag, lead, rows, tall):
    """lead: lines of a plain row before the span (0 = none); rows: lines of the three spanned rows;
    tall: True = right cell holds that many paragraphs; False = one line, the row's height set (atLeast)."""
    out = ['<w:p><w:pPr><w:pageBreakBefore/><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:t>%s</w:t></w:r></w:p>' % tag]
    t = ['<w:tbl><w:tblPr><w:tblW w:w="%d" w:type="dxa"/><w:tblBorders>' % (WA + WB + WC)
         + ''.join('<w:%s w:val="single" w:sz="4"/>' % s for s in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'))
         + '</w:tblBorders></w:tblPr><w:tblGrid><w:gridCol w:w="%d"/><w:gridCol w:w="%d"/><w:gridCol w:w="%d"/></w:tblGrid>' % (WA, WB, WC)]
    def right(name, n):
        return (cell(WC, paras(name, n)), None) if tall else (cell(WC, P % (name + '-1')), n * LINE)
    if lead:
        c, h = right(tag + '-lead', lead)
        t.append(row([cell(WA, P % (tag + '-plainA')), cell(WB, P % (tag + '-plainB')), c], h))
    for i, n in enumerate(rows):
        c, h = right('%s-r%d' % (tag, i + 1), n)
        a = cell(WA, P % (tag + '-K'), 'r') if i == 0 else cell(WA, P % '', 'c')
        t.append(row([a, cell(WB, P % ('%s-b%d' % (tag, i + 1))), c], h))
    c, h = right(tag + '-tail', 1)
    t.append(row([cell(WA, P % (tag + '-tailA')), cell(WB, P % (tag + '-tailB')), c], h))
    t.append('</w:tbl>')
    out.append(''.join(t))
    out.append(P % 'end')
    return ''.join(out)
# tag: (lead lines, (r1, r2, r3) lines, tall right cell)
CASES = [
    ('A', 0, (5, 5, 5), True),   # 12 table lines a page: rows 1-2 = 10, the foot falls inside row 3
    ('B', 0, (6, 6, 3), True),   # rows 1-2 end exactly at the foot, row 3 on the next page
    ('C', 0, (4, 10, 4), True),  # the foot falls inside row 2
    ('D', 0, (3, 9, 5), True),   # rows 1-2 end exactly at the foot
    ('E', 2, (4, 4, 6), True),   # the span starts under a plain row; the foot inside row 3
    ('F', 0, (3, 3, 3), True),   # control: everything fits
    ('G', 0, (2, 2, 12), True),  # the foot far inside row 3
    ('H', 0, (8, 3, 6), True),   # rows 1-2 = 11 lines, row 3 parts after 1 line
    ('I', 0, (5, 5, 5), False),  # as A, the heights set by trHeight, every cell one line
    ('J', 0, (6, 6, 3), False),  # as B, likewise
]
body = ''.join(table(t, l, r, tall) for t, l, r, tall in CASES)
doc = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s'
       '<w:sectPr><w:pgSz w:w="8400" w:h="6000"/><w:pgMar w:top="1000" w:right="720" w:bottom="1000" w:left="720" w:header="400" w:footer="400" w:gutter="0"/></w:sectPr></w:body></w:document>') % (W, body)
ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
out = sys.argv[1] if len(sys.argv) > 1 else 'cm4.docx'
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', ct); z.writestr('_rels/.rels', rels); z.writestr('word/document.xml', doc)
