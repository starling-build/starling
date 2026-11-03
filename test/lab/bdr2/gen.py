import zipfile,sys
CT='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
RELS='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DR='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>'
SET='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>'
W='xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
BD='<w:pBdr><w:top w:val="single" w:sz="24" w:space="4" w:color="000000"/><w:left w:val="single" w:sz="24" w:space="4" w:color="000000"/><w:bottom w:val="single" w:sz="24" w:space="4" w:color="000000"/><w:right w:val="single" w:sz="24" w:space="4" w:color="000000"/>%s</w:pBdr>'
def para(runs,before=0,after=0,shade=None,between=False,bdr=True):
    p='<w:pPr>'
    if bdr: p+=BD%('<w:between w:val="single" w:sz="12" w:space="2" w:color="FF0000"/>' if between else '')
    if shade: p+='<w:shd w:val="clear" w:color="auto" w:fill="%s"/>'%shade
    p+='<w:spacing w:before="%d" w:after="%d"/>'%(before*20,after*20)+'</w:pPr>'
    return '<w:p>'+p+runs+'</w:p>'
def t(s): return '<w:r><w:t xml:space="preserve">%s</w:t></w:r>'%s
PB='<w:r><w:br w:type="page"/></w:r>'; CB='<w:r><w:br w:type="column"/></w:r>'
def doc(body,cols=1):
    c='<w:cols w:num="2" w:space="720"/>' if cols==2 else ''
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>%s</w:sectPr></w:body></w:document>'%(W,body,c)
def head(s): return para(t(s),bdr=False)
cases={}
Y='FFFF99'
for sh,tag in ((Y,'s'),(None,'n')):
    for bf in (0,40):
        cases[f'b1{tag}{bf}']=doc(head('lead')+para(t('AAA')+PB+t('BBB'),before=bf,shade=sh))      # fragment split by a page break
        cases[f'b2{tag}{bf}']=doc(head('lead')+para(PB+t('BBB'),before=bf,shade=sh))              # empty first fragment
        cases[f'b3{tag}{bf}']=doc(head('lead')+para(t('AAA')+PB,before=bf,shade=sh)+para(t('CCC'),before=bf,shade=sh))  # break ends paragraph, then an identical one
        cases[f'b4{tag}{bf}']=doc(head('lead')+para(t('AAA')+CB+t('BBB'),before=bf,shade=sh),cols=2)  # column break in 2 columns
        cases[f'b5{tag}{bf}']=doc(head('lead')+para(t('AAA'),before=bf,after=10,shade=sh)+para(t('BBB'),before=bf,after=10,shade=sh)+para(t('CCC'),before=bf,after=10,shade=sh))  # three identical
        cases[f'b6{tag}{bf}']=doc(head('lead')+para(t('AAA'),before=bf,after=10,shade=sh,between=True)+para(t('BBB'),before=bf,after=10,shade=sh,between=True))  # with w:between
import os
os.makedirs('out',exist_ok=True)
for n,x in cases.items():
    z=zipfile.ZipFile(f'out/bdr2_{n}.docx','w',zipfile.ZIP_DEFLATED)
    z.writestr('[Content_Types].xml',CT); z.writestr('_rels/.rels',RELS); z.writestr('word/_rels/document.xml.rels',DR); z.writestr('word/settings.xml',SET); z.writestr('word/document.xml',x); z.close()
print(len(cases))
