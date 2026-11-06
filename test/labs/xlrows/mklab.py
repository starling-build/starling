import zipfile,sys,os
out=sys.argv[1]; os.makedirs(out,exist_ok=True)
def font(name,sz,b=False,scheme=False):
    return f'<font>{"<b/>" if b else ""}<sz val="{sz}"/><name val="{name}"/><family val="2"/></font>'
def make(fn,fonts,sheetfmt,rows,cols='',merge='',scale=100):
    # fonts: list; xf i uses font i. rows: list of (style idx, ht or None, text, wrap)
    xfs=''.join(f'<xf numFmtId="0" fontId="{i}" fillId="0" borderId="0" xfId="0" applyFont="1"{" applyAlignment=\"1\"><alignment wrapText=\"1\" vertical=\"bottom\"/></xf>" if w else "/>"}' for i,w in [(i,(i in WRAP.get(fn,()))) for i in range(len(fonts))])
    styles=f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="{len(fonts)}">{"".join(fonts)}</fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="{len(fonts)}">{xfs}</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'
    rx=''
    for n,(st,ht,txt) in enumerate(rows,1):
        h=f' ht="{ht}"' if ht else ''
        rx+=f'<row r="{n}"{h}>'+''.join(f'<c r="{c}{n}" s="{st}" t="inlineStr"><is><t>{txt} {c}{n}</t></is></c>' for c in "ABC")+'</row>'
    sheet=f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetPr><pageSetUpPr fitToPage="0"/></sheetPr><sheetViews><sheetView workbookViewId="0"/></sheetViews>{sheetfmt}{cols or "<cols><col min=\"1\" max=\"3\" width=\"24\" customWidth=\"1\"/></cols>"}<sheetData>{rx}</sheetData>{merge}<printOptions gridLines="1"/><pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/><pageSetup paperSize="1" scale="{scale}" orientation="portrait"/></worksheet>'
    z=zipfile.ZipFile(f'{out}/{fn}.xlsx','w',zipfile.ZIP_DEFLATED)
    z.writestr('[Content_Types].xml','<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>')
    z.writestr('_rels/.rels','<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
    z.writestr('xl/workbook.xml','<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Lab" sheetId="1" r:id="rId1"/></sheets></workbook>')
    z.writestr('xl/_rels/workbook.xml.rels','<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>')
    z.writestr('xl/styles.xml',styles); z.writestr('xl/worksheets/sheet1.xml',sheet); z.close()
WRAP={'row-wrapheader-ht15':(1,)}
N=40
plain=lambda st,t='Row',ht=None:[(st,ht,t)]*N
# default-font cases: default font only, with sheetFormatPr variants
for face,sz in [("Verdana",10),("Calibri",11),("Arial",10),("Malgun Gothic",10),("Segoe UI",8),("Verdana",9),("Calibri",10)]:
    for tag,fmt in [("d15",'<sheetFormatPr defaultRowHeight="15"/>'),("d1275",'<sheetFormatPr defaultRowHeight="12.75"/>'),("d1275b",'<sheetFormatPr baseColWidth="10" defaultRowHeight="12.75"/>')]:
        if face!="Verdana" and tag!="d15" and (face,sz)!=("Arial",10): continue
        make(f'row-{face.replace(" ","")}{sz}-{tag}',[font(face,sz)],fmt,plain(0))
# Segoe UI 8 cells in a Calibri 11 book (lo-tdf76115) and Calibri 10 in 11
for face,sz in [("Segoe UI",8),("Calibri",10),("Arial",9),("Verdana",10)]:
    make(f'row-calibri11book-cells-{face.replace(" ","")}{sz}',[font("Calibri",11),font(face,sz)],'<sheetFormatPr defaultRowHeight="15"/>',plain(1))
# a row with bigger text, no customHeight, every 5th row; and ht set but not custom
rows=[(1,None,'Big') if i%5==0 else (0,None,'Row') for i in range(1,N+1)]
make('row-bigtext-nocustom',[font("Calibri",11),font("Calibri",20)],'<sheetFormatPr defaultRowHeight="15"/>',rows)
rows=[(0,30,'Ht30') if i%5==0 else (0,None,'Row') for i in range(1,N+1)]
make('row-ht30-nocustom',[font("Calibri",11)],'<sheetFormatPr defaultRowHeight="15"/>',rows)
# wrapped header row, Arial 9 bold, ht 18 not custom, merged A:C; then data rows Arial 9 and Calibri 11
WRAP['row-wrapheader']=(1,)
long='Nomination Point Name for the gas network and its long header text that must wrap across lines'
rows=[(1,18,long)]+[(2,None,'Gas')]*3+[(0,None,'Row')]*(N-4)
make('row-wrapheader',[font("Calibri",11),font("Arial",9,True),font("Arial",9)],'<sheetFormatPr defaultRowHeight="15"/>',rows,cols='<cols><col min="1" max="3" width="9" customWidth="1"/></cols>',merge='<mergeCells count="1"><mergeCell ref="A1:B1"/></mergeCells>')
make('row-wrapheader-ht15',[font("Calibri",11),font("Arial",9,True),font("Arial",9)],'<sheetFormatPr defaultRowHeight="15"/>',[(1,15,long)]+rows[1:],cols='<cols><col min="1" max="3" width="9" customWidth="1"/></cols>',merge='<mergeCells count="1"><mergeCell ref="A1:B1"/></mergeCells>')
