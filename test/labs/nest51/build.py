#!/usr/bin/env python3
"""Lab nest51 (from lo-51b81ccd): where does Word put the left edge of a table whose tblInd is negative or zero,
nested in a zero-margin outer cell vs at top level, as border width, cell margin and compat mode vary?
Each doc varies ONE thing across 5 tables on a page. Measure the x of the inner table's left border edge and text.
usage: build.py OUTDIR"""
import sys, os, zipfile
CT='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
RELS='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DRELS='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>'
SETT='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="{M}"/></w:compat></w:settings>'
W='xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
def p(t="",sz=20): return f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="{sz}"/></w:rPr><w:t xml:space="preserve">{t}</w:t></w:r></w:p>'
def bord(sz):
    b=f'w:val="single" w:sz="{sz}" w:space="0" w:color="000000"'
    return f'<w:tcBorders><w:top {b}/><w:left {b}/><w:bottom {b}/><w:right {b}/></w:tcBorders>' if sz else ''
def inner(ind,cm,bw,label):
    c=f'<w:tcPr><w:tcW w:w="1500" w:type="dxa"/>{bord(bw)}</w:tcPr>'
    return (f'<w:tbl><w:tblPr><w:tblW w:w="3000" w:type="dxa"/><w:tblInd w:w="{ind}" w:type="dxa"/><w:tblLayout w:type="fixed"/>'
            f'<w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="{cm}" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="{cm}" w:type="dxa"/></w:tblCellMar></w:tblPr>'
            f'<w:tblGrid><w:gridCol w:w="1500"/><w:gridCol w:w="1500"/></w:tblGrid><w:tr><w:trPr><w:trHeight w:val="400" w:hRule="atLeast"/></w:trPr><w:tc>{c}{p(label)}</w:tc><w:tc>{c}{p("b")}</w:tc></w:tr></w:tbl>')
def outer(inn):
    return ('<w:tbl><w:tblPr><w:tblW w:w="6000" w:type="dxa"/><w:tblInd w:w="0" w:type="dxa"/><w:tblLayout w:type="fixed"/>'
            '<w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="0" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar></w:tblPr>'
            '<w:tblGrid><w:gridCol w:w="3100"/><w:gridCol w:w="2900"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="3100" w:type="dxa"/></w:tcPr>'
            f'{inn}{p()}</w:tc><w:tc><w:tcPr><w:tcW w:w="2900" w:type="dxa"/></w:tcPr>{p()}</w:tc></w:tr></w:tbl>')
IND=[-120,-60,0,60,120]; CM=[0,85,170]; BW=[0,4,24,48]
# (code, description, mode, list of (nested?, ind, cm, bw))
DOCS=[]
for m in (15,12):
    DOCS.append((f"ind{m}",f"mode {m}: nested, tblInd -120..120, cm 85, border 6pt",m,[(1,i,85,48) for i in IND]))
    DOCS.append((f"top{m}",f"mode {m}: top level, tblInd -120..120, cm 85, border 6pt",m,[(0,i,85,48) for i in IND]))
DOCS.append(("bw15","mode 15: nested, tblInd -60, cm 85, border 0/0.5/3/6pt",15,[(1,-60,85,b) for b in BW]))
DOCS.append(("cm15","mode 15: nested, tblInd -60, border 6pt, cm 0/85/170",15,[(1,-60,c,48) for c in CM]))
DOCS.append(("cmz15","mode 15: nested, tblInd 0, border 6pt, cm 0/85/170",15,[(1,0,c,48) for c in CM]))
def build(out):
    for code,desc,mode,rows in DOCS:
        body=""
        for n,(nest,ind,cm,bw) in enumerate(rows):
            lab=f"{code} #{n+1} ind{ind} cm{cm} bw{bw}"
            body+=p(lab,14)
            t=inner(ind,cm,bw,"T")
            body+=(outer(t) if nest else t)+p()+p()
        doc=(f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{body}'
             '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>')
        path=os.path.join(out,f"nest51-{code}.docx")
        with zipfile.ZipFile(path,"w",zipfile.ZIP_DEFLATED) as z:
            z.writestr("[Content_Types].xml",CT);z.writestr("_rels/.rels",RELS)
            z.writestr("word/_rels/document.xml.rels",DRELS);z.writestr("word/document.xml",doc);z.writestr("word/settings.xml",SETT.replace("{M}",str(mode)))
        print(path,"-",desc)
if __name__=="__main__":
    os.makedirs(sys.argv[1],exist_ok=True);build(sys.argv[1])
