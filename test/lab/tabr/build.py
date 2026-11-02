#!/usr/bin/env python3
"""Lab tabr (Windows 01QbbApP, for amd-7): right tab stops with dot leader just past the right margin. A4 (11910 wide), margins 1531 -> text width 8848.
Lines 'Entry N<tab>12' with a RIGHT dot-leader tab at 8848 (ref), 8900..9300 step 50; three blocks: SimSun 14pt, Times New Roman 14pt, SimHei 16pt (dot pitch).
usage: build.py OUTDIR -> OUTDIR/tabr.docx"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
STOPS = [8848] + list(range(8900, 9301, 50))
BLOCKS = [('SimSun', 14, 'S'), ('Times New Roman', 14, 'T'), ('SimHei', 16, 'H')]
def para(face, pt, tag, i, pos):
    rp = '<w:rFonts w:ascii="%s" w:hAnsi="%s" w:eastAsia="%s" w:cs="%s"/><w:sz w:val="%d"/><w:szCs w:val="%d"/>' % (face, face, face, face, pt * 2, pt * 2)
    return ('<w:p><w:pPr><w:tabs><w:tab w:val="right" w:leader="dot" w:pos="%d"/></w:tabs><w:spacing w:before="0" w:after="0" w:line="360" w:lineRule="exact"/><w:rPr>%s</w:rPr></w:pPr>'
            '<w:r><w:rPr>%s</w:rPr><w:t>Entry %s%d</w:t></w:r><w:r><w:rPr>%s</w:rPr><w:tab/><w:t>12</w:t></w:r></w:p>') % (pos, rp, rp, tag, i, rp)
body = ''.join(para(f, pt, tag, i, pos) for f, pt, tag in BLOCKS for i, pos in enumerate(STOPS))
doc = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s<w:sectPr><w:pgSz w:w="11910" w:h="16850"/><w:pgMar w:top="1440" w:right="1531" w:bottom="1440" w:left="1531" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>' % (NS, body))
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
R = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
os.makedirs(sys.argv[1], exist_ok=True)
with zipfile.ZipFile(os.path.join(sys.argv[1], 'tabr.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', R); z.writestr('word/document.xml', doc)
print(len(STOPS) * len(BLOCKS), 'lines')
