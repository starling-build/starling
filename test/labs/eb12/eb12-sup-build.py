import zipfile
W='xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
RP='<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="22"/>'
def run(t,sup=False): return f'<w:r><w:rPr>{RP}{"<w:vertAlign w:val=\"superscript\"/>" if sup else ""}</w:rPr><w:t xml:space="preserve">{t}</w:t></w:r>'
def para(runs,before=113,line=240): return f'<w:p><w:pPr><w:spacing w:before="{before}" w:after="0" w:line="{line}" w:lineRule="auto"/></w:pPr>{runs}</w:p>'
def tbl(cellparas,mar=28):
    return ('<w:tbl><w:tblPr><w:tblW w:w="1698" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblBorders><w:top w:val="single" w:sz="4" w:color="808080"/><w:bottom w:val="single" w:sz="4" w:color="808080"/><w:left w:val="single" w:sz="4" w:color="808080"/><w:right w:val="single" w:sz="4" w:color="808080"/></w:tblBorders><w:tblCellMar><w:left w:w="28" w:type="dxa"/><w:right w:w="28" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid><w:gridCol w:w="1698"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="1698" w:type="dxa"/>'
            f'<w:tcMar><w:top w:w="{mar}" w:type="dxa"/><w:bottom w:w="{mar}" w:type="dxa"/></w:tcMar></w:tcPr>{cellparas}</w:tc></w:tr></w:tbl>')
txt_sup=run("Draai T ' U ")+run("2",True)+run(" en ga naar 2 . 4")
txt_plain=run("Draai T ' U 2 en ga naar 2 . 4")
cases=[('sup in cell',tbl(para(txt_sup))),('plain in cell',tbl(para(txt_plain))),('sup at start',tbl(para(run("2",True)+run(" Draai T ' U en ga naar 2 . 4")))),('sup only line2',tbl(para(run("Draai T ' U en ga naar ")+run("2",True)+run(" . 4")))),('sup para',para(txt_sup)),('plain para',para(txt_plain))]
body=''
for n,(name,xml) in enumerate(cases,1):
    pb='<w:pageBreakBefore/>' if n>1 else ''
    body+=f'<w:p><w:pPr>{pb}<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:rPr><w:sz w:val="20"/></w:rPr><w:t>CASE {n} {name}</w:t></w:r></w:p>{xml}'
    body+=f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:rPr>{RP}</w:rPr><w:t>END{n}</w:t></w:r></w:p>'
sect='<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>'
doc=f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{body}{sect}</w:body></w:document>'
ct='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
rels='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
z=zipfile.ZipFile('sup.docx','w',zipfile.ZIP_DEFLATED); z.writestr('[Content_Types].xml',ct); z.writestr('_rels/.rels',rels); z.writestr('word/document.xml',doc); z.close()
