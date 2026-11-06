# kash3 = kash1 plus a settings.xml (compat 15), indents 0..400 step 25. Kashida lab (lo-af36644e): Persian paragraphs set jc both/lowKashida/mediumKashida/highKashida, at six widths
# (right indent), with short, middle and long words, plus the document's own sentence with the 50-tatweel word.
# Question: does Word reserve a share of the line (per line) or room at each word gap (per word)?
import zipfile
NS='xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
SHORT='و من به در از با که این را بر او'
MID='متن فارسی با جملات خیلی طولانی و'
LONG='طولانیترین کلمههای فارسیزبانان بزرگترین'
DOC='متن فارسی با کلمات کوتاه. متن فارسی با کلمات خی'+'ی'*50+'لی طولانی. متن فارسی با جملات خیلی طولانی و متن فارسی با جملات خیلی طولانی و متن فارسی با جملات خیلی طولانی.'
def rep(w,n): return ' '.join([w]*n)
TXT=[('mid',rep(MID,9)),('long',rep(LONG,6))]
JC=['both','lowKashida','mediumKashida','highKashida']
IND=list(range(0,401,25))
def lab(t): return '<w:p><w:pPr><w:spacing w:before="160" w:after="0"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="14"/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r></w:p>'%t
def rtl(jc,ind,t):
    return ('<w:p><w:pPr><w:bidi/><w:spacing w:after="0"/><w:ind w:left="%d" w:right="0"/><w:jc w:val="%s"/></w:pPr><w:r><w:rPr><w:rFonts w:cs="Arial" w:hint="cs"/><w:rtl/><w:szCs w:val="24"/><w:lang w:bidi="fa-IR"/></w:rPr><w:t>%s</w:t></w:r></w:p>')%(ind*20,jc,t)
body=''
for name,t in TXT:
    for jc in JC:
        for i in IND:
            body+=lab('%s %s indent %d pt'%(name,jc,i))+rtl(jc,i,t)
for jc in JC:
    for i in (0,100,250):
        body+=lab('doc %s indent %d pt'%(jc,i))+rtl(jc,i,DOC)
doc='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1000" w:right="1440" w:bottom="1000" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>'%(NS,body)
z=zipfile.ZipFile('kash3.docx','w',zipfile.ZIP_DEFLATED)
z.writestr('[Content_Types].xml','<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
z.writestr('_rels/.rels','<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
z.writestr('word/document.xml',doc)
z.writestr('word/_rels/document.xml.rels','<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>')
z.writestr('word/settings.xml','<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>')
z.writestr('word/styles.xml',zipfile.ZipFile('../kash2/kash2.docx').read('word/styles.xml'))
z.close()
