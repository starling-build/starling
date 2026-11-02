#!/usr/bin/env python3
"""Lab asd (Windows 01QbbApP, for amd-opus): when does Word insert the automatic space between an ideograph and a digit.
mode 15, characterSpacingControl compressPunctuation, 15pt, useFELayout, no balanceSingleByteDoubleByteWidth. Ideograph runs: eastAsia 宋体.
Digit run "30" between ideographs: 5 rFonts variants x docDefaults eastAsia in {宋体, Times New Roman}.  jc left, one paragraph per variant.
gen.py OUT"""
import sys, os, zipfile
W_ = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
TNR = 'Times New Roman'
SONG = '宋体'
DIG = {
    '1none': '',
    '2tnr-ascii-hansi': '<w:rFonts w:ascii="%s" w:hAnsi="%s"/>' % (TNR, TNR),
    '3tnr-ascii-hansi-hintEA': '<w:rFonts w:ascii="%s" w:hAnsi="%s" w:hint="eastAsia"/>' % (TNR, TNR),
    '4tnr-all-three': '<w:rFonts w:ascii="%s" w:hAnsi="%s" w:eastAsia="%s"/>' % (TNR, TNR, TNR),
    '5song-ascii-hansi-hintEA': '<w:rFonts w:ascii="%s" w:hAnsi="%s" w:hint="eastAsia"/>' % (SONG, SONG),
}
IDE = '<w:rFonts w:eastAsia="%s"/>' % SONG


def r(rpr, t):
    return '<w:r><w:rPr>%s<w:sz w:val="30"/><w:szCs w:val="30"/><w:lang w:eastAsia="zh-CN"/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r>' % (rpr, t)


def pkg(path, ddea):
    body = ''
    for k, rf in DIG.items():
        body += '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="400" w:lineRule="exact"/></w:pPr>%s%s%s</w:p>' % (r(IDE, '测试文字'), r(rf, '30'), r(IDE, '测试文字'))
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/><w:docGrid w:linePitch="312"/></w:sectPr>'
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W_, body, sect)
    sty = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles %s><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:eastAsia="%s" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>'
           '<w:sz w:val="30"/><w:szCs w:val="30"/><w:lang w:val="en-US" w:eastAsia="zh-CN" w:bidi="ar-SA"/></w:rPr></w:rPrDefault></w:docDefaults>'
           '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>' % (W_, ddea))
    st = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings %s><w:characterSpacingControl w:val="compressPunctuation"/><w:compat><w:useFELayout/>'
          '<w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>' % W_)
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
    root = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    dr = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        for n, v in (('[Content_Types].xml', ct), ('_rels/.rels', root), ('word/document.xml', doc), ('word/styles.xml', sty), ('word/settings.xml', st), ('word/_rels/document.xml.rels', dr)):
            z.writestr(n, v)


if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    pkg(os.path.join(out, 'asd-ddsong.docx'), SONG)
    pkg(os.path.join(out, 'asd-ddtnr.docx'), TNR)
    print('ok')
