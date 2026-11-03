#!/usr/bin/env python3
"""Lab tbl14w (for Windows Word, from lenovo-5): how wide is a table cell's text area, by border style/width and
cell margin, in compat 14 and 15? A one-cell fixed table of width W holds "MMMMMMMM" (Courier New 12pt, 8 x 7.2 =
57.6pt = 1152 twips). It sets on one line when the cell's text area is at least that wide, and wraps otherwise; W
steps 4 twips (0.2pt) from 1152-20+2*margin to +84, so the width at which the line stops wrapping gives the text
area: area = W - 2*margin - (what the borders take).
usage: build.py OUTDIR -> t14w.docx, t15w.docx. Print each to PDF; meas.py PDF reads one row per table."""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
STYLES_B = {'single6': ('single', 6), 'outset6': ('outset', 6), 'inset6': ('inset', 6), 'double6': ('double', 6),
            'thickThin18': ('thickThinSmallGap', 18), 'single24': ('single', 24)}
MARGINS = {'m0': 0, 'm108': 108}
DELTAS = list(range(-20, 88, 4))
def table(b, m, d):
    kind, sz = STYLES_B[b]; mar = MARGINS[m]
    w = 1152 + 2 * mar + d
    bd = ''.join(f'<w:{s} w:val="{kind}" w:sz="{sz}" w:space="0" w:color="000000"/>' for s in ('top', 'left', 'bottom', 'right'))
    pr = (f'<w:tblPr><w:tblW w:w="{w}" w:type="dxa"/><w:tblInd w:w="0" w:type="dxa"/><w:tblBorders>{bd}</w:tblBorders><w:tblLayout w:type="fixed"/>'
          f'<w:tblCellMar><w:left w:w="{mar}" w:type="dxa"/><w:right w:w="{mar}" w:type="dxa"/></w:tblCellMar></w:tblPr>')
    run = '<w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/><w:sz w:val="24"/></w:rPr>'
    cell = f'<w:tc><w:tcPr><w:tcW w:w="{w}" w:type="dxa"/></w:tcPr><w:p><w:pPr><w:spacing w:after="0"/></w:pPr><w:r>{run}<w:t>MMMMMMMM</w:t></w:r></w:p></w:tc>'
    return f'<w:tbl>{pr}<w:tblGrid><w:gridCol w:w="{w}"/></w:tblGrid><w:tr>{cell}</w:tr></w:tbl>'
def build():
    body = ''; n = 0; labels = []
    for b in STYLES_B:
        for m in MARGINS:
            for d in DELTAS:
                n += 1; lab = f'T{n} {b} {m} d{d}'; labels.append(lab)
                body += f'<w:p><w:pPr><w:spacing w:before="60" w:after="40"/></w:pPr><w:r><w:t>{lab}</w:t></w:r></w:p>' + table(b, m, d)
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{body}<w:p/>{sect}</w:body></w:document>', labels
STYLES = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>'
def settings(mode): return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {NS}><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="{mode}"/></w:compat></w:settings>'
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DRELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>'
if __name__ == '__main__':
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    doc, labels = build()
    for mode in (14, 15):
        with zipfile.ZipFile(os.path.join(out, f't{mode}w.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS); z.writestr('word/document.xml', doc)
            z.writestr('word/styles.xml', STYLES); z.writestr('word/settings.xml', settings(mode)); z.writestr('word/_rels/document.xml.rels', DRELS)
    print(len(labels), 'tables per file')
