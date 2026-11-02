import zipfile
W='xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
def p(t,sz=22,line=360,extra=''): 
    return f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="{line}" w:lineRule="auto"/>{extra}</w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="{sz}"/></w:rPr><w:t>{t}</w:t></w:r></w:p>'
def tail(sz):  # trailing empty paragraph, default style, size sz
    return f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="{sz}"/></w:rPr></w:pPr></w:p>'
def nested(rows,trh=None):
    tr=''.join(f'<w:tr>'+(f'<w:trPr><w:trHeight w:val="{trh}"/></w:trPr>' if trh else '')+f'<w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr>{p("n%d"%k)}</w:tc></w:tr>' for k in range(rows))
    return f'<w:tbl><w:tblPr><w:tblW w:w="3000" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="10" w:type="dxa"/><w:right w:w="10" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid><w:gridCol w:w="3000"/></w:tblGrid>{tr}</w:tbl>'
def outer(rows,trh,tailsz,mar):
    cm=f'<w:tcMar><w:top w:w="{mar}" w:type="dxa"/><w:bottom w:w="{mar}" w:type="dxa"/></w:tcMar>' if mar else ''
    return ('<w:tbl><w:tblPr><w:tblW w:w="7000" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblBorders><w:top w:val="single" w:sz="4" w:color="808080"/><w:bottom w:val="single" w:sz="4" w:color="808080"/><w:left w:val="single" w:sz="4" w:color="808080"/><w:right w:val="single" w:sz="4" w:color="808080"/><w:insideV w:val="single" w:sz="4" w:color="808080"/></w:tblBorders><w:tblCellMar><w:left w:w="10" w:type="dxa"/><w:right w:w="10" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid><w:gridCol w:w="3500"/><w:gridCol w:w="3500"/></w:tblGrid><w:tr>'
      f'<w:tc><w:tcPr><w:tcW w:w="3500" w:type="dxa"/>{cm}</w:tcPr>{p("Draai text")}</w:tc>'
      f'<w:tc><w:tcPr><w:tcW w:w="3500" w:type="dxa"/>{cm}</w:tcPr>{nested(rows,trh)}{tail(tailsz)}</w:tc></w:tr></w:tbl>')
cases=[(1,None,24,0),(2,None,24,0),(2,None,4,0),(2,391,24,0),(2,None,48,0),(2,None,24,28),(3,None,24,0),(0,None,24,0)]
body=''
for n,(rows,trh,ts,mar) in enumerate(cases,1):
    pb='<w:pageBreakBefore/>' if n>1 else ''
    body+=f'<w:p><w:pPr>{pb}<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="20"/></w:rPr><w:t>CASE {n} rows={rows} trh={trh} tail={ts} mar={mar}</w:t></w:r></w:p>'
    if rows==0:
        # reference: no nested table, one plain paragraph + tail
        body+=outer(1,None,ts,mar).replace(nested(1,None),p("plain"))
    else: body+=outer(rows,trh,ts,mar)
    body+=p(f'END{n}',sz=22,line=240)
sect='<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>'
doc=f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{body}{sect}</w:body></w:document>'
ct='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
rels='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
z=zipfile.ZipFile('nest.docx','w',zipfile.ZIP_DEFLATED); z.writestr('[Content_Types].xml',ct); z.writestr('_rels/.rels',rels); z.writestr('word/document.xml',doc); z.close()
