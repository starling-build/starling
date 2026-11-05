#!/usr/bin/env python3
"""Lab rtlhead (for lo-7ec36a70): RTL (bidi) paragraphs, Arial, shaded so each print shows the line box.
24 paragraphs: run size 12/15/20pt x mark szCs unset/10/15/20pt x spacing (before,after) = (0,0) or (12,12) pt... see table in the doc.
Order: for spacing in (0, 12): for run in (12,15,20): for markcs in (0,10,15,20). Each paragraph: bidi, Persian text, text shaded grey.
Usage: build.py OUT.docx. Print to PDF; report per paragraph: the grey box top/bottom and the text baseline (pt from page top)."""
import sys, zipfile
out = sys.argv[1]
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
body = ''
n = 0
for sp in (0, 12):
    for run in (12, 15, 20):
        for mcs in (0, 10, 15, 20):
            n += 1
            mark = f'<w:rPr><w:sz w:val="{run*2}"/>' + (f'<w:szCs w:val="{mcs*2}"/>' if mcs else '') + '</w:rPr>'
            body += (f'<w:p><w:pPr><w:bidi/><w:shd w:val="clear" w:color="auto" w:fill="D9D9D9"/><w:spacing w:before="{sp*20}" w:after="{sp*20}"/>'
                     f'<w:rPr><w:rFonts w:ascii="Arial" w:cs="Arial"/><w:sz w:val="{run*2}"/>' + (f'<w:szCs w:val="{mcs*2}"/>' if mcs else '') + '<w:rtl/></w:rPr></w:pPr>'
                     f'<w:r><w:rPr><w:rFonts w:ascii="Arial" w:cs="Arial"/><w:sz w:val="{run*2}"/><w:szCs w:val="{run*2}"/><w:rtl/></w:rPr><w:t>{n:02d} صفحه یک sp{sp} run{run} mark{mcs}</w:t></w:r></w:p>')
doc = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{body}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>'
ct = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
rels = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
z = zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED)
z.writestr('[Content_Types].xml', ct); z.writestr('_rels/.rels', rels); z.writestr('word/document.xml', doc); z.close()
