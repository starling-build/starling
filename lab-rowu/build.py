#!/usr/bin/env python3
"""build.py OUTDIR -> ru-arial10.xlsx, ru-verdana10.xlsx (Windows 01QbbApP, for amd-6). Layout as lab-rowi: one sheet, no row heights, thin bottom border on every cell.
Rows 1-5   : A = 'Xg' 10pt, underline none/single/double/singleAccounting/doubleAccounting
Rows 6-10  : A = 'Xg' 16pt plain, B = 'Xg' 10pt with the five underline kinds
Rows 11-15 : A = 'Xg' 16pt with the five underline kinds (extra set)
Row 16     : A = 'Xg' 16pt plain control. Default font of the book and the cells' face: Arial 10 / Verdana 10."""
import sys, os, zipfile
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
U = [('none', ''), ('single', '<u/>'), ('double', '<u val="double"/>'), ('singleAcc', '<u val="singleAccounting"/>'), ('doubleAcc', '<u val="doubleAccounting"/>')]
def build(face):
    fonts = [f'<font><sz val="10"/><name val="{face}"/></font>']; xfs = ['<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>']
    def xf(sz, u):
        fonts.append(f'<font>{u}<sz val="{sz}"/><name val="{face}"/></font>')
        xfs.append(f'<xf numFmtId="0" fontId="{len(fonts)-1}" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>'); return len(xfs) - 1
    rows = []; r = 0
    def row(cells):
        nonlocal r; r += 1
        rows.append(f'<row r="{r}">' + ''.join(f'<c r="{c}{r}" s="{s}" t="inlineStr"><is><t>{t}</t></is></c>' for c, s, t in cells) + '</row>')
    for n, u in U: row([('A', xf(10, u), f'Xg {n}')])
    for n, u in U: row([('A', xf(16, ''), 'Xg 16'), ('B', xf(10, u), f'Xg {n}')])
    for n, u in U: row([('A', xf(16, u), f'Xg 16 {n}')])
    row([('A', xf(16, ''), 'Xg 16 control')])
    sheet = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:B%d"/><sheetViews><sheetView workbookViewId="0"/></sheetViews><sheetFormatPr defaultRowHeight="15"/><cols><col min="1" max="2" width="30" customWidth="1"/></cols><sheetData>%s</sheetData></worksheet>' % (r, ''.join(rows)))
    styles = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="%d">%s</fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FFFF0000"/></bottom><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="%d">%s</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>' % (len(fonts), ''.join(fonts), len(xfs), ''.join(xfs)))
    return sheet, styles
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
WB = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>'
WR = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
for name, face in (('ru-arial10', 'Arial'), ('ru-verdana10', 'Verdana')):
    sheet, styles = build(face)
    with zipfile.ZipFile(os.path.join(out, name + '.xlsx'), 'w', zipfile.ZIP_DEFLATED) as z:
        for fn, b in (('[Content_Types].xml', CT), ('_rels/.rels', RELS), ('xl/workbook.xml', WB), ('xl/_rels/workbook.xml.rels', WR), ('xl/worksheets/sheet1.xml', sheet), ('xl/styles.xml', styles)): z.writestr(fn, b)
print('ok')
