#!/usr/bin/env python3
"""Lab kashida: regenerates docx/. usage: build.py [OUTDIR]"""
import sys, os, zipfile
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'docx')
os.makedirs(out, exist_ok=True)
JCS = ['both', 'lowKashida', 'mediumKashida', 'highKashida']
RIGHTS = [0, 200, 400, 800]            # right indent, twips: text width 453.6pt minus 0, 10, 20, 40pt
SAMPLE = 'This is a sample text. This is another sample text. This is also a longlonglonglonglonglong text. ' * 4
WORDS = ' '.join(['word'] * 150)
def esc(s): return s.replace('&', '&amp;').replace('<', '&lt;')
def para(text, jc=None, right=0, bold=False):
    ppr = ''
    if right: ppr += '<w:ind w:right="%d"/>' % right
    if jc: ppr += '<w:jc w:val="%s"/>' % jc
    rpr = '<w:rPr><w:b/></w:rPr>' if bold else ''
    return '<w:p><w:pPr>%s</w:pPr><w:r>%s<w:t xml:space="preserve">%s</w:t></w:r></w:p>' % (ppr, rpr, esc(text))
def build(name, text, pagebreak_each):
    body = ''
    for jc in JCS:
        for r in RIGHTS:
            body += para('%s / right %d twips' % (jc, r), None, 0, True)
            body += para(text, jc, r)
        if pagebreak_each: body += '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'
    doc = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'
           + body + '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>')
    styles = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr>'
              '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault>'
              '<w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="259" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults></w:styles>')
    settings = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>'
    ct = ('<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
          '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
    rels = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    drels = ('<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
             '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
             '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
    with zipfile.ZipFile(os.path.join(out, name), 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', ct); z.writestr('_rels/.rels', rels)
        z.writestr('word/document.xml', doc); z.writestr('word/styles.xml', styles)
        z.writestr('word/settings.xml', settings); z.writestr('word/_rels/document.xml.rels', drels)
build('kash-01-sample.docx', SAMPLE, True)
build('kash-02-words.docx', WORDS, True)
print('wrote', out)
