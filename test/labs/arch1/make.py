# Arch WordArt lab (lo-677416be's two shapes): textArchUp, Georgia, path width, box height and font size varied one at a time.
import zipfile
EMU=12700
NS=('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')
n=[0]
def shape(text,cx,cy,sz):
    n[0]+=1
    return ('<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="%d" cy="%d"/><wp:docPr id="%d" name="a%d"/>'
     '<a:graphic><a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"><wps:wsp><wps:cNvSpPr txBox="1"/>'
     '<wps:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="%d" cy="%d"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></wps:spPr>'
     '<wps:txbx><w:txbxContent><w:p><w:r><w:rPr><w:rFonts w:ascii="Georgia" w:hAnsi="Georgia"/><w:sz w:val="%d"/><w:szCs w:val="%d"/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r></w:p></w:txbxContent></wps:txbx>'
     '<wps:bodyPr wrap="none" fromWordArt="1" lIns="0" rIns="0" tIns="0" bIns="0" anchor="t"><a:prstTxWarp prst="textArchUp"><a:avLst><a:gd name="adj" fmla="val 10800000"/></a:avLst></a:prstTxWarp><a:noAutofit/></wps:bodyPr>'
     '</wps:wsp></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>')%(cx,cy,n[0],n[0],cx,cy,sz*2,sz*2,text)
def para(label,x=''):
    return '<w:p><w:pPr><w:spacing w:before="120" w:after="0"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="14"/></w:rPr><w:t>%s</w:t></w:r></w:p><w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr>%s</w:p>'%(label,x)
T=[(" Air Quality Roundtable",104.74,11.59,10),("Williams Lake",63.75,8.65,10)]
body=''
for t,w0,h0,s0 in T:
    nm=t.strip()
    for k in (0.5,0.7,0.85,1.0,1.2,1.5,2.0):   # path width, size and height fixed
        body+=para('%s: width x%.2f (%.1f pt), height %.1f, size %d'%(nm,k,w0*k,h0,s0),shape(t,round(w0*k*EMU),round(h0*EMU),s0))
    for h in (0.5,1.5,2.0,3.0):                 # box height only
        body+=para('%s: height x%.1f (%.1f pt), width %.1f, size %d'%(nm,h,h0*h,w0,s0),shape(t,round(w0*EMU),round(h0*h*EMU),s0))
    for s in (6,8,9,11,12,14,18):               # size only
        body+=para('%s: size %d, width %.1f, height %.1f'%(nm,s,w0,h0),shape(t,round(w0*EMU),round(h0*EMU),s))
doc='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1000" w:right="1000" w:bottom="1000" w:left="1000" w:header="500" w:footer="500" w:gutter="0"/></w:sectPr></w:body></w:document>'%(NS,body)
z=zipfile.ZipFile('arch1.docx','w',zipfile.ZIP_DEFLATED)
z.writestr('[Content_Types].xml','<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
z.writestr('_rels/.rels','<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
z.writestr('word/document.xml',doc)
