#!/usr/bin/env python3
"""Lab smallcaps (Windows 01QbbApP, for amd-4): one docx, one paragraph per line, left aligned, no spacing, <w:smallCaps/>.
Lines: TNR then Arial at 9,10,11,12,13,14pt, 'Lorem ipsum dolor sit amet, Consectetur Adipiscing'; then 11pt mixed-case lines (both faces) and 11pt/13pt/9.5pt/10.5 half-point sizes.
usage: build.py OUTDIR -> OUTDIR/smallcaps.docx"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
S = "Lorem ipsum dolor sit amet, Consectetur Adipiscing"
M = "LoReM iPsUm dOlOr SiT aMeT, cOnSeCtEtUr AdIpIsCiNg"
L = []
for face in ("Times New Roman", "Arial"):
    for pt in (9, 10, 11, 12, 13, 14): L.append((face, pt, S))
for face in ("Times New Roman", "Arial"):
    L.append((face, 11, M))
for face in ("Times New Roman", "Arial"):
    for pt in (9.5, 10.5, 11.5, 12.5): L.append((face, pt, S))
def para(face, pt, t):
    return ('<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="%s" w:hAnsi="%s" w:cs="%s"/><w:smallCaps/><w:sz w:val="%d"/><w:szCs w:val="%d"/></w:rPr><w:t>%s</w:t></w:r></w:p>'
            % (face, face, face, round(pt * 2), round(pt * 2), t))
body = ''.join(para(*x) for x in L)
doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>' % (NS, body)
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
R = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
os.makedirs(sys.argv[1], exist_ok=True)
with zipfile.ZipFile(os.path.join(sys.argv[1], 'smallcaps.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', R); z.writestr('word/document.xml', doc)
print(len(L), 'lines')
