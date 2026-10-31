#!/usr/bin/env python3
"""Lab as14: how much of the page bottom a footer takes from the body (macOS-doc, 2026-10-31, T252;
LibreOffice's floattable-header needs Word's body to end >= 2pt lower than ours with a 2-line 8pt footer).
A4, margins top 72 / bottom 28.35 (567 twips) / footer distance 35.45 (709) unless stated; the body is
numbered one-line paragraphs L01.. of Times New Roman 12 (single, 0 before/after), 70 of them (> a page).
The footer: LINES paragraphs of "F1".."Fn" at SIZE pt, Times New Roman, single, 0 before/after
(variant 'sp' = the LO document's docDefaults: 259/240 line, 8pt after).
usage: build.py OUTDIR      Word for Windows -> PDF; report per document the LAST body line on page 1
(its text and y, PDF text top, pt) and the page count; also the y of F1 on page 1."""
import os, sys, zipfile

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
W = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
     'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')

def body():
    return ''.join('<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="24"/></w:rPr><w:t>L%02d</w:t></w:r></w:p>' % n for n in range(1, 71))

def footer(lines, size, spaced):
    sp = '<w:spacing w:before="0" w:after="160" w:line="259" w:lineRule="auto"/>' if spaced else '<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>'
    ps = ''.join('<w:p><w:pPr>%s</w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="%d"/></w:rPr><w:t>F%d</w:t></w:r></w:p>' % (sp, size * 2, n + 1) for n in range(lines))
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:ftr %s>%s</w:ftr>' % (W, ps)

def doc(dist, bottom):
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s'
            '<w:sectPr><w:footerReference w:type="default" r:id="rId2"/><w:pgSz w:w="11906" w:h="16838"/>'
            '<w:pgMar w:top="1440" w:right="1440" w:bottom="%d" w:left="1440" w:header="708" w:footer="%d" w:gutter="0"/></w:sectPr></w:body></w:document>' % (W, body(), bottom, dist))

CT = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
      '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
DRELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
         '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>'
         '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/></Relationships>')
SET = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings %s><w:compat><w:compatSetting w:name="compatibilityMode" '
       'w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>' % W)

variants = []
for lines in (1, 2, 3):
    for size in (8, 10, 12):
        variants.append(('f%d-s%d' % (lines, size), lines, size, False, 709, 567))
variants.append(('f2-s8-spaced', 2, 8, True, 709, 567))
variants.append(('f2-s8-dist400', 2, 8, False, 400, 567))
variants.append(('f2-s8-dist1000', 2, 8, False, 1000, 567))
variants.append(('f2-s8-bottom1440', 2, 8, False, 709, 1440))
variants.append(('f0-none', 0, 8, False, 709, 567))

for name, lines, size, spaced, dist, bottom in variants:
    fn = os.path.join(out, 'as14-%s.docx' % name)
    with zipfile.ZipFile(fn, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS)
        z.writestr('word/_rels/document.xml.rels', DRELS); z.writestr('word/settings.xml', SET)
        z.writestr('word/document.xml', doc(dist, bottom))
        z.writestr('word/footer1.xml', footer(max(lines, 1), size, spaced))
    print(fn)
