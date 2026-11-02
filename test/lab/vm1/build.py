#!/usr/bin/env python3
"""Lab vm1 (Windows 01QbbApP, for amd-5): vMerge-restart left cell taller than the two rows it spans. Left col 34pt (680tw) CJK chars one per line (exact 16pt),
right col 4000tw, row1 3 paragraphs exact 12pt, row2 4 paragraphs exact 12pt, tcMar 0 top/bottom, single borders.
a) trHeight atLeast 976 on both rows, 6 chars; b) same, 2 chars; c) trHeight 0 (no min), 6 chars.
usage: build.py OUTDIR -> a.docx b.docx c.docx"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'

def cp(t, line): return f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="{line}" w:lineRule="exact"/></w:pPr><w:r><w:rPr><w:rFonts w:eastAsia="新細明體"/></w:rPr><w:t>{t}</w:t></w:r></w:p>'
B = ''.join(f'<w:{e} w:val="single" w:sz="4" w:space="0" w:color="000000"/>' for e in ('top', 'left', 'bottom', 'right'))
MAR = '<w:tcMar><w:top w:w="0" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/></w:tcMar>'
def tc(w, inner, vm=None):
    v = f'<w:vMerge w:val="restart"/>' if vm == 'r' else ('<w:vMerge/>' if vm == 'c' else '')
    return f'<w:tc><w:tcPr><w:tcW w:w="{w}" w:type="dxa"/>{v}{MAR}</w:tcPr>{inner}</w:tc>'
def tbl(nchar, trh):
    h = f'<w:trPr><w:trHeight w:val="{trh}" w:hRule="atLeast"/></w:trPr>' if trh else ''
    chars = ''.join(cp(c, 320) for c in '一二三四五六'[:nchar])
    r1 = f'<w:tr>{h}' + tc(680, chars, 'r') + tc(4000, ''.join(cp(f'row1 line{k}', 240) for k in range(1, 4))) + '</w:tr>'
    r2 = f'<w:tr>{h}' + tc(680, cp('', 240), 'c') + tc(4000, ''.join(cp(f'row2 line{k}', 240) for k in range(1, 5))) + '</w:tr>'
    return (f'<w:tbl><w:tblPr><w:tblW w:w="4680" w:type="dxa"/><w:tblBorders>{B}<w:insideH w:val="single" w:sz="4" w:space="0" w:color="000000"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="000000"/></w:tblBorders><w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr>'
            '<w:tblGrid><w:gridCol w:w="680"/><w:gridCol w:w="4000"/></w:tblGrid>' + r1 + r2 + '</w:tbl><w:p/>')
V = {'a': tbl(6, 976), 'b': tbl(2, 976), 'c': tbl(6, 0)}
def doc(body):
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{body}{sect}</w:body></w:document>'
STYLES = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>'
SET = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {NS}><w:trackRevisions/></w:settings>'
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DRELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>'
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
for code, body in V.items():
    with zipfile.ZipFile(os.path.join(out, code + '.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS)
        z.writestr('word/document.xml', doc(body)); z.writestr('word/styles.xml', STYLES)
        z.writestr('word/settings.xml', SET); z.writestr('word/_rels/document.xml.rels', DRELS)
print(len(V), 'docs')
