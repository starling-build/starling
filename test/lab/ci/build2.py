#!/usr/bin/env python3
"""(variant: distinct chars 甲乙丙丁戊己庚辛, indents 0..36pt) Lab ci (Windows 01QbbApP, for amd-6, zh-08e95de4): centred paragraph with a first-line indent wider than the cell's text width.
One doc, seven one-cell tables (fixed layout, tblCellMar left/right 108), each preceded by a label line 'T:<key>'; cell text "甲乙丙丁戊己庚辛", jc center, line exact 300 (15pt), font 新細明體 12pt (ascii Times New Roman).
keys: i0 i10 i20 i31 i40 at cell width 675tw (33.75pt); w45 w60 at indent 624 (31.2pt). (i31 = case (a) = (c) 31.2 = (d) 33.75.)  Also runs with SimSun 'ss' (indent 624, w 675) as the font may matter.
usage: build.py OUTDIR -> OUTDIR/ci.docx, cases.txt"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
CASES = [('d0', 675, 0), ('d16', 675, 320), ('d20', 675, 400), ('d24', 675, 480), ('d28', 675, 560), ('d31', 675, 624), ('d36', 675, 720)]
def rf(k): return '<w:rFonts w:ascii="SimSun" w:hAnsi="SimSun" w:eastAsia="SimSun"/>' if k == 'ss' else '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="新細明體"/>'
def block(k, w, ind):
    lab = f'<w:p><w:pPr><w:spacing w:before="240" w:after="0"/></w:pPr><w:r><w:t>T:{k}</w:t></w:r></w:p>'
    cell = (f'<w:tc><w:tcPr><w:tcW w:w="{w}" w:type="dxa"/></w:tcPr><w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="300" w:lineRule="exact"/>'
            f'<w:ind w:firstLine="{ind}"/><w:jc w:val="center"/></w:pPr><w:r><w:rPr>{rf(k)}<w:sz w:val="24"/></w:rPr><w:t>甲乙丙丁戊己庚辛</w:t></w:r></w:p></w:tc>')
    t = (f'<w:tbl><w:tblPr><w:tblW w:w="{w}" w:type="dxa"/><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
         '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/></w:tblBorders><w:tblLayout w:type="fixed"/>'
         '<w:tblCellMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr>'
         f'<w:tblGrid><w:gridCol w:w="{w}"/></w:tblGrid><w:tr>{cell.replace("<w:tc>", "<w:tc>", 1)}</w:tr></w:tbl>')
    return lab + t
BODY = ''.join(block(*c) for c in CASES)
sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1800" w:bottom="1440" w:left="1800" w:header="851" w:footer="992" w:gutter="0"/></w:sectPr>'
DOC = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{BODY}{sect}</w:body></w:document>'
STYLES = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="新細明體"/><w:sz w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault/></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>'
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DRELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
with zipfile.ZipFile(os.path.join(out, 'ci2.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS); z.writestr('word/document.xml', DOC)
    z.writestr('word/styles.xml', STYLES); z.writestr('word/_rels/document.xml.rels', DRELS)
print(len(CASES), 'tables')
