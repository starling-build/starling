# lab pfr (for amd-5): page foot rule for a page-anchored floating one-row table. Landscape, 1in margins, header/footer 35.4pt (708 tw), footer present.
# Row: trHeight atLeast 1014 tw (50.7pt), 8 paragraphs of exact 13.4pt (268 tw), text "Snn Lk".
# doc pfH: 16 sections, page height 600..630pt step 2 (w stays 792), tblpY = 10814 tw (540.7pt).
# doc pfY: 16 sections, page height 612, tblpY 500..560pt step 4 (tw = pt*20).
# doc pfB: 12 sections, page height 612, tblpY 540.7pt, bottom margin 0.5in..1.5in stepped (720..2160 tw step 130).
import sys, zipfile, os
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
def sect(h, bot=1440, last=False):
    return ('<w:sectPr><w:footerReference w:type="default" r:id="rId2"/><w:pgSz w:w="15840" w:h="%d" w:orient="landscape"/><w:pgMar w:top="1440" w:right="1440" w:bottom="%d" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>' % (h, bot))
def block(i, y, two=False):
    ps = ''.join('<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="268" w:lineRule="exact"/></w:pPr><w:r><w:rPr><w:sz w:val="20"/></w:rPr><w:t>S%02d L%d</w:t></w:r></w:p>' % (i, k) for k in range(1, 9))
    return ('<w:tbl><w:tblPr><w:tblpPr w:leftFromText="0" w:rightFromText="0" w:vertAnchor="page" w:horzAnchor="page" w:tblpX="1440" w:tblpY="%d"/><w:tblW w:w="3000" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="0" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid><w:gridCol w:w="3000"/></w:tblGrid>'
            '%s<w:tr><w:trPr><w:trHeight w:val="1014" w:hRule="atLeast"/></w:trPr><w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr>%s</w:tc></w:tr></w:tbl>'
            '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/></w:pPr></w:p>') % (y, ('<w:tr><w:trPr><w:trHeight w:val="1014" w:hRule="exact"/></w:trPr><w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr><w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr><w:r><w:rPr><w:sz w:val="20"/></w:rPr><w:t>R1</w:t></w:r></w:p></w:tc></w:tr>' if two else ''), ps)
def doc(secs):
    body = ''
    for n, (h, y, bot) in enumerate(secs):
        body += block(n + 1, y, TWO)
        s = sect(h, bot)
        body += ('<w:p><w:pPr>%s</w:pPr></w:p>' % s) if n < len(secs) - 1 else ''
    last = secs[-1]
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (NS, body, sect(last[0], last[2]))
FOOT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:ftr %s><w:p><w:r><w:rPr><w:sz w:val="20"/></w:rPr><w:t>F</w:t></w:r></w:p></w:ftr>' % NS
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DR = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/></Relationships>'
TWO = len(sys.argv) > 2
DOCS = {'pfH': [(h * 20, 10814 - (1014 if TWO else 0), 1440) for h in range(600, 632, 2)],
        'pfY': [(12240, y * 20 - (1014 if TWO else 0), 1440) for y in range(500, 564, 4)],
        'pfB': [(12240, 10814 - (1014 if TWO else 0), 720 + 130 * k) for k in range(12)]}
for k, secs in DOCS.items():
    with zipfile.ZipFile(os.path.join(out, k + ('t' if TWO else '') + '.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS); z.writestr('word/document.xml', doc(secs))
        z.writestr('word/footer1.xml', FOOT); z.writestr('word/_rels/document.xml.rels', DR)
print({k: len(v) for k, v in DOCS.items()})
