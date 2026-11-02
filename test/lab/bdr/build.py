#!/usr/bin/env python3
"""Lab bdr (Windows 01QbbApP, for amd-2): does a paragraph's border+shading cover its spacing-before (60pt)?
Letter, margins 72pt, TNR 12. Bordered paragraph = pBdr top/left/bottom/right single sz24 space 1/4/1/4 + shd E2EFD9, before=1200 after=0.
 bdrA: plain line then 'mid'.  bdrB: 'first' alone first on page.  bdrC: page-break paragraph then 'afterbreak'.  bdrD: 2 columns, bordered 'colA' ending in a column break then bordered 'aftercol' (the two merge into one box).
 bdrE: 2 columns, plain 'col1' ending in a column break then bordered 'aftercol'.
usage: build.py OUTDIR"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
BP = ('<w:pBdr><w:top w:val="single" w:sz="24" w:space="1" w:color="auto"/><w:left w:val="single" w:sz="24" w:space="4" w:color="auto"/>'
      '<w:bottom w:val="single" w:sz="24" w:space="1" w:color="auto"/><w:right w:val="single" w:sz="24" w:space="4" w:color="auto"/></w:pBdr>'
      '<w:shd w:val="clear" w:color="auto" w:fill="E2EFD9"/><w:spacing w:before="1200" w:after="0"/>')
def bp(t, extra=''): return f'<w:p><w:pPr>{extra}{BP}</w:pPr><w:r><w:t>{t}</w:t></w:r></w:p>'
def pl(t): return f'<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr><w:r><w:t>{t}</w:t></w:r></w:p>'
PB = '<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr><w:r><w:br w:type="page"/></w:r></w:p>'
CB = '<w:r><w:br w:type="column"/></w:r>'
SP = '<w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>'
def doc(body, cols=1):
    c = '<w:cols w:num="2" w:space="720"/>' if cols == 2 else ''
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{body}<w:sectPr>{SP}{c}</w:sectPr></w:body></w:document>'
D = {'bdrA': doc(pl('plain line') + bp('mid')), 'bdrB': doc(bp('first')), 'bdrC': doc(pl('page one') + PB + bp('afterbreak')),
     'bdrD': doc(bp('colA') .replace('</w:p>', CB + '</w:p>') + bp('aftercol'), 2),
     'bdrE': doc(pl('col1') .replace('</w:p>', CB + '</w:p>') + bp('aftercol'), 2)}
STYLES = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="Times New Roman"/><w:sz w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault/></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>'
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DRELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
for k, v in D.items():
    with zipfile.ZipFile(os.path.join(out, k + '.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS); z.writestr('word/document.xml', v)
        z.writestr('word/styles.xml', STYLES); z.writestr('word/_rels/document.xml.rels', DRELS)
print(len(D), 'docs')
