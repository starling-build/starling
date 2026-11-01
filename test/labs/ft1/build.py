#!/usr/bin/env python3
"""Lab ft1 (Windows 01QbbApP, for amd-6): where does Word cut a page-anchored floating table's row at the page foot?
usage: build.py OUTDIR. Landscape Letter (15840x12240, or A4-landscape-height 11906 for the 595pt page), margins 1440, header/footer 708.
Floating table: tblpPr vertAnchor=page horzAnchor=margin tblpY 3286, fixed layout, one column 5800. Rows: S1.. = empty spacer rows of exact height (at most 90pt each, summing to Y - table top) so the next row starts at Y,
T = a row of ~7 lines of Calibri 11 text (starts at Y), U = a second 7-line row after it.  Y is measured from the page top, in pt: body bottom is 540 (612pt page) or 523.3 (595pt page)."""
import sys, os, zipfile

TOP = 3286 / 20.0   # table top, pt
LOREM = ("Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua Ut enim ad minim veniam "
         "quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore "
         "eu fugiat nulla pariatur Excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum")
# (name, page height twips, Y pt, compat mode)
CASES = []
for mode in (12, 15):
    for tag, y in (("a-20", 520.0), ("b-0", 540.0), ("c+3", 543.0), ("d+15", 555.0)):
        CASES.append((f"ft1-{tag}-m{mode}", 12240, y, mode))
CASES.append(("ft1-c+3-m12-p595", 11906, 526.3, 12))
CASES.append(("ft1-c+3-m15-p595", 11906, 526.3, 15))
for y in (580.0, 600.0, 606.0, 611.0):
    CASES.append((f"ft1-y{int(y)}-m12", 12240, y, 12))
FOOTER = {"ft1-c+3-m12-footer": (12240, 543.0, 12), "ft1-c+3-m15-footer": (12240, 543.0, 15)}
for k, (ph, y, mode) in FOOTER.items():
    CASES.append((k, ph, y, mode))

W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'


def para(text):
    return f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:t>{text}</w:t></w:r></w:p>'


def cell(inner):
    return f'<w:tc><w:tcPr><w:tcW w:w="5800" w:type="dxa"/></w:tcPr>{inner}</w:tc>'


def build(path, ph, y, mode, footer=False):
    spacer = round((y - TOP) * 20)
    # spacer rows of at most 90pt (exact), like the 7-line rows of the real document, summing to Y - TOP
    chunks = []
    left = spacer
    while left > 0:
        c = min(left, 1800)
        chunks.append(c)
        left -= c
    rows = ''.join(f'<w:tr><w:trPr><w:trHeight w:val="{c}" w:hRule="exact"/></w:trPr>{cell(para("S%d" % (k + 1)))}</w:tr>' for k, c in enumerate(chunks))
    rows += (f'<w:tr>{cell(para("T " + LOREM))}</w:tr>'
             f'<w:tr>{cell(para("U " + LOREM))}</w:tr>')
    tbl = ('<w:tbl><w:tblPr><w:tblpPr w:leftFromText="0" w:rightFromText="0" w:vertAnchor="page" w:horzAnchor="margin" w:tblpY="3286"/>'
           '<w:tblW w:w="5800" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr>'
           '<w:tblGrid><w:gridCol w:w="5800"/></w:tblGrid>' + rows + '</w:tbl>')
    body = para("ft1") + tbl + '<w:p/>'
    sect = (f'<w:sectPr><w:pgSz w:w="15840" w:h="{ph}" w:orient="landscape"/>'
            '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>')
    if footer:
        sect = sect.replace('<w:pgMar', '<w:footerReference w:type="default" r:id="rId3"/><w:pgMar', 1)
    document = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W} xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>{body}{sect}</w:body></w:document>'
    styles = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {W}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/>'
              '<w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
              '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>')
    settings = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {W}><w:compat><w:compatSetting w:name="compatibilityMode" '
                f'w:uri="http://schemas.microsoft.com/office/word" w:val="{mode}"/></w:compat></w:settings>')
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
          '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
    root = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
    drels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
             '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
             '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
    if footer:
        ct = ct.replace('</Types>', '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/></Types>')
        drels = drels.replace('</Relationships>', '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/></Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", ct)
        z.writestr("_rels/.rels", root)
        z.writestr("word/document.xml", document)
        z.writestr("word/styles.xml", styles)
        z.writestr("word/settings.xml", settings)
        z.writestr("word/_rels/document.xml.rels", drels)
        if footer:
            z.writestr("word/footer1.xml", f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:ftr {W}><w:p><w:r><w:t>Footer</w:t></w:r></w:p></w:ftr>')


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name, ph, y, mode in CASES:
        build(os.path.join(out, name + ".docx"), ph, y, mode, footer=name.endswith('-footer'))
        print(name)
