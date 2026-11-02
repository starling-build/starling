#!/usr/bin/env python3
"""Lab cambria (Windows 01QbbApP, for lenovo-5): Cambria first baseline and line pitch per size.
One paragraph per page (A4, margins 72 all round, compat 15, docDefaults Cambria on all four slots, spacing 0, line 240 auto, no grid), 6 lines each made with <w:br/>.
Pages: 12pt, 48pt, 11pt, 10pt, then 48pt text whose line-break runs and paragraph mark are 12pt (the tdf153136 case), then bold 48, italic 48.
gen.py OUT"""
import sys, os, zipfile
W_ = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
CASES = [('s12', 12, '', 12), ('s48', 48, '', 48), ('s11', 11, '', 11), ('s10', 10, '', 10), ('s48br12', 48, '', 12), ('b48', 48, '<w:b/>', 48), ('i48', 48, '<w:i/>', 48)]
RF = '<w:rFonts w:ascii="Cambria" w:hAnsi="Cambria" w:eastAsia="Cambria" w:cs="Cambria"/>'


def run(sz, extra, inner):
    return '<w:r><w:rPr>%s%s<w:sz w:val="%d"/><w:szCs w:val="%d"/></w:rPr>%s</w:r>' % (RF, extra, sz * 2, sz * 2, inner)


def para(k, sz, extra, brsz):
    pb = '' if k == 0 else '<w:pageBreakBefore/>'
    runs = ''
    for i in range(6):
        runs += run(sz, extra, '<w:t>Hxg %d Cambria line</w:t>' % (i + 1))
        if i < 5:
            runs += run(brsz, extra, '<w:br/>')
    ppr = '<w:pPr>%s<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/><w:rPr>%s<w:sz w:val="%d"/></w:rPr></w:pPr>' % (pb, RF, brsz * 2)
    return '<w:p>%s%s</w:p>' % (ppr, runs)


def pkg(path):
    body = ''.join(para(k, sz, ex, br) for k, (n, sz, ex, br) in enumerate(CASES))
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W_, body, sect)
    sty = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles %s><w:docDefaults><w:rPrDefault><w:rPr>%s<w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:rPrDefault>'
           '<w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
           '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>' % (W_, RF))
    st = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings %s><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>' % W_)
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
    pkg(os.path.join(out, 'cambria.docx'))
    print('ok')
