#!/usr/bin/env python3
"""build3.py -> ef3.docx (amd-3, lo-eb12e7d4 p14): the ef lab with what FOLLOWS the empty paragraph varied.
Two columns, 10pt Times, picture line 1.5 spacing then an empty 1.5 paragraph with 6.35pt to spare at the column foot
(ef lab: ours == Word for the bare case). Variants, one per page: what comes after the empty paragraph."""
import zipfile, io, re
exec(open("build.py").read().split("for cols in")[0])
NUM = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="multilevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="338" w:hanging="283"/></w:pPr></w:lvl><w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1.%2"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="338" w:hanging="283"/></w:pPr></w:lvl></w:abstractNum><w:num w:numId="3"><w:abstractNumId w:val="0"/></w:num></w:numbering>'
LONG = 'Two lines of text that need the width of the column and a little more to wrap round'
H = 67
def item(t, sp=SP15, ppr=''): return para(t, sp, '', ppr)
VAR = [
 ('a plain 2 lines, widow on', lambda k: item('T%d-NEXT %s' % (k, LONG))),
 ('b plain 2 lines, widow off', lambda k: item('T%d-NEXT %s' % (k, LONG), ppr='<w:widowControl w:val="0"/>')),
 ('c numbered 2 lines, widow off', lambda k: item('T%d-NEXT %s' % (k, LONG), ppr='<w:widowControl w:val="0"/><w:numPr><w:ilvl w:val="1"/><w:numId w:val="3"/></w:numPr>')),
 ('d one line', lambda k: item('T%d-NEXT one line' % k)),
 ('e numbered 1 line', lambda k: item('T%d-NEXT one line' % k, ppr='<w:numPr><w:ilvl w:val="1"/><w:numId w:val="3"/></w:numPr>')),
 ('f 2 lines at single spacing', lambda k: para('T%d-NEXT %s' % (k, LONG), SP1)),
]
def variant3(k, name, nxt):
    out = [para('T%d %s' % (k, name), ppr='<w:pageBreakBefore/>' if k else '')]
    for i in range(1, FILL + 1): out.append(para('T%d-f%d' % (k, i)))
    out.append(para('', SP15, inline(40, H)))
    out.append(para('', SP15))
    out.append(nxt(k))
    for i in range(1, 4): out.append(para('T%d-z%d' % (k, i)))
    return ''.join(out)
doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W, ''.join(variant3(k, n, f) for k, (n, f) in enumerate(VAR)), sect(2))
ct3 = ct.replace('<Override PartName="/word/document.xml"', '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/><Override PartName="/word/document.xml"')
drels3 = drels.replace('</Relationships>', '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/></Relationships>')
with zipfile.ZipFile('ef3.docx', 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', ct3); z.writestr('_rels/.rels', rels); z.writestr('word/document.xml', doc)
    z.writestr('word/_rels/document.xml.rels', drels3); z.writestr('word/media/p.png', png.getvalue()); z.writestr('word/numbering.xml', NUM)
