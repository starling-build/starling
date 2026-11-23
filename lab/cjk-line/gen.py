# CJK line lab round 1 (amd-3, 2026-11-23): faces x sizes, default (single-line, no ht) and wrapped rows, at print scale 100 and 83.
import zipfile
from xml.sax.saxutils import escape
FACES=[("PMingLiU","新細明體"),("MingLiU","細明體"),("SimSun","宋体"),("JhengHei","微軟正黑體")]
SIZES=[9,10,11,12,14,16]
CJK="這是一段用來測試換行高度的中文文字，包含標點與數字123和English字母，直到超過三行為止。"*2
def build(scale):
    fonts=['<font><sz val="11"/><name val="Calibri"/><family val="2"/></font>']
    xfs=['<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>']
    sid={}
    for _,fn in FACES:
        for s in SIZES:
            fonts.append(f'<font><sz val="{s}"/><name val="{fn}"/><family val="3"/><charset val="136"/></font>')
            fi=len(fonts)-1
            xfs.append(f'<xf numFmtId="0" fontId="{fi}" fillId="0" borderId="0" xfId="0" applyFont="1"/>')
            sid[(fn,s,0)]=len(xfs)-1
            xfs.append(f'<xf numFmtId="0" fontId="{fi}" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf>')
            sid[(fn,s,1)]=len(xfs)-1
    ns='xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
    rns='xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
    styles=f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet {ns}><fonts count="{len(fonts)}">{"".join(fonts)}</fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="{len(xfs)}">{"".join(xfs)}</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'
    sheets=[]
    for ln,fn in FACES:
        rows=[]
        for i,s in enumerate(SIZES):
            r1=2*i+1
            lab=f"{ln}{s}"
            rows.append(f'<row r="{r1}"><c r="A{r1}" s="{sid[(fn,s,0)]}" t="inlineStr"><is><t>{lab} 單行Ag</t></is></c></row>')
            r2=r1+1
            rows.append(f'<row r="{r2}"><c r="A{r2}" s="{sid[(fn,s,1)]}" t="inlineStr"><is><t>{escape(lab)}{CJK}</t></is></c></row>')
        sheets.append(f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet {ns}><sheetPr><pageSetUpPr fitToPage="0"/></sheetPr><sheetFormatPr defaultRowHeight="15"/><cols><col min="1" max="1" width="30" customWidth="1"/></cols><sheetData>{"".join(rows)}</sheetData><pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/><pageSetup paperSize="9" scale="{scale}" orientation="portrait"/></worksheet>')
    wb=f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook {ns} {rns}><sheets>'+"".join(f'<sheet name="{n}" sheetId="{i+1}" r:id="rId{i+1}"/>' for i,(n,_) in enumerate(FACES))+'</sheets></workbook>'
    rel='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'+"".join(f'<Relationship Id="rId{i+1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet{i+1}.xml"/>' for i in range(4))+f'<Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
    ct='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'+"".join(f'<Override PartName="/xl/worksheets/sheet{i+1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' for i in range(4))+'</Types>'
    root='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
    with zipfile.ZipFile(f"cjk-line-{scale}.xlsx","w",zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml",ct); z.writestr("_rels/.rels",root); z.writestr("xl/workbook.xml",wb)
        z.writestr("xl/_rels/workbook.xml.rels",rel); z.writestr("xl/styles.xml",styles)
        for i,sx in enumerate(sheets): z.writestr(f"xl/worksheets/sheet{i+1}.xml",sx)
for sc in (100,83): build(sc)
