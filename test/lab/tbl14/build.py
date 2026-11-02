#!/usr/bin/env python3
"""Lab tbl14 (for Windows Word, from lenovo-5): where does a table's text start in a cell, by compat mode,
cell margin, border width/style, table indent, width kind?
usage: build.py OUTDIR -> t14.docx (compat 14) and t15.docx (compat 15), same tables in both.
Times New Roman 12, A4, 1in margins. Each table = a label paragraph "T<n> ..." then a 2-row x 2-col table whose
cells read AAAA | BBBB (row 1) and CCCC | DDDD (row 2). Print each to PDF; meas.py reads rule x and text x."""
import sys, os, zipfile, itertools
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
BORDERS = {'s4': ('single', 4), 's12': ('single', 12), 's24': ('single', 24), 'o6': ('outset', 6)}   # eighths of a point
MARGINS = {'m0': 0, 'm28': 28, 'm108': 108}       # twips, table-level tblCellMar left & right
INDENTS = {'i0': 0, 'im108': -108, 'i108': 108}
WIDTHS = {'pct': ('pct', 5000), 'dxa': ('dxa', 8000), 'auto': ('auto', 0)}
LAYOUTS = {'autofit': None, 'fixed': 'fixed'}
def table(b, m, ind, w, lay, widthcell):
    kind, bsz = BORDERS[b]
    bd = ''.join(f'<w:{s} w:val="{kind}" w:sz="{bsz}" w:space="0" w:color="000000"/>' for s in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'))
    wk, wv = WIDTHS[w]
    lay_x = f'<w:tblLayout w:type="{LAYOUTS[lay]}"/>' if LAYOUTS[lay] else ''
    mar = MARGINS[m]
    pr = (f'<w:tblPr><w:tblW w:w="{wv}" w:type="{wk}"/><w:tblInd w:w="{INDENTS[ind]}" w:type="dxa"/><w:tblBorders>{bd}</w:tblBorders>{lay_x}'
          f'<w:tblCellMar><w:left w:w="{mar}" w:type="dxa"/><w:right w:w="{mar}" w:type="dxa"/></w:tblCellMar></w:tblPr>')
    grid = '<w:tblGrid><w:gridCol w:w="4000"/><w:gridCol w:w="4000"/></w:tblGrid>'
    def cell(t): return f'<w:tc><w:tcPr><w:tcW w:w="{4000 if wk=="dxa" or lay=="fixed" else 0}" w:type="{"dxa" if wk=="dxa" or lay=="fixed" else "auto"}"/></w:tcPr><w:p><w:pPr><w:spacing w:after="0"/></w:pPr><w:r><w:t>{t}</w:t></w:r></w:p></w:tc>'
    rows = ''.join(f'<w:tr>{cell(a)}{cell(c)}</w:tr>' for a, c in (('AAAA', 'BBBB'), ('CCCC', 'DDDD')))
    return f'<w:tbl>{pr}{grid}{rows}</w:tbl>'
def build(compat):
    body = ''; labels = []
    n = 0
    for b, m, ind, w, lay in itertools.product(BORDERS, MARGINS, INDENTS, ('pct', 'dxa'), ('autofit', 'fixed')):
        n += 1; lab = f'T{n} {b} {m} {ind} {w} {lay}'; labels.append(lab)
        body += f'<w:p><w:pPr><w:spacing w:before="120" w:after="60"/></w:pPr><w:r><w:t>{lab}</w:t></w:r></w:p>' + table(b, m, ind, w, lay, None)
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    doc = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{body}<w:p/>{sect}</w:body></w:document>'
    return doc, labels
STYLES = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>'
def settings(mode): return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {NS}><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="{mode}"/></w:compat></w:settings>'
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DRELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>'
if __name__ == '__main__':
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    for mode in (14, 15):
        doc, labels = build(mode)
        with zipfile.ZipFile(os.path.join(out, f't{mode}.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS); z.writestr('word/document.xml', doc)
            z.writestr('word/styles.xml', STYLES); z.writestr('word/settings.xml', settings(mode)); z.writestr('word/_rels/document.xml.rels', DRELS)
    print(len(labels), 'tables per file')
