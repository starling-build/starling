#!/usr/bin/env python3
"""Lab rowpitch2 (lenovo-3, for macos): the follow-up of lab rowpitch. Its table-level rules (tblBorders) give
Word's pitch = row height + rule, as ours does; but lo tdf152298, whose rules are CELL-level (tcBorders: left and
bottom on each cell, none on top), steps 16.08pt a row in Word's print (317 twips atLeast), ours 16.10.
Run from the repository root: python3 test/labs/rowpitch2/build.py

Twelve documents, each ONE table of 40 rows in one fixed column, a short "x" in each row (Times New Roman 12pt,
single spacing, no space before/after, cell margins 0 top and bottom, A4 margin 1134), rows atLeast 317 twips:
  c<where>-<sz>.docx   where = bottom (tcBorders bottom only) / top (top only) / both (top and bottom)
                       sz    = 2 / 4 / 8  (0.25 / 0.5 / 1pt)
  t-s2 / t-s4 / t-s8   control: the same rows with tblBorders (all sides and inside lines) of that size
Read with test/labs/rowpitch2/meas.py DIR: the mean pitch to 0.001pt, the spread and the running total, and the
first row's top.  Question: how much of a cell-level rule goes into a row's height (all, half, nothing)?
"""
import os, zipfile
OUT = "test/labs/rowpitch2/docx/"
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DOCRELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>'
SETTINGS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>'
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
STYLES = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {W}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>'
def build(name, mode, where, sz):
    """mode 'cell': tcBorders on `where` of every cell; mode 'tbl': tblBorders of size sz."""
    if mode == "tbl":
        tb = "".join(f'<w:{s} w:val="single" w:sz="{sz}" w:space="0" w:color="000000"/>' for s in ("top", "left", "bottom", "right", "insideH", "insideV"))
        tcb = ""
    else:
        tb = ""
        sides = {"bottom": ("bottom",), "top": ("top",), "both": ("top", "bottom")}[where]
        tcb = "<w:tcBorders>" + "".join(f'<w:{s} w:val="single" w:sz="{sz}" w:space="0" w:color="000000"/>' for s in sides) + "</w:tcBorders>"
    tr = '<w:trPr><w:trHeight w:val="317" w:hRule="atLeast"/></w:trPr>'
    rows = f'<w:tr>{tr}<w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/>{tcb}</w:tcPr><w:p><w:r><w:t>x</w:t></w:r></w:p></w:tc></w:tr>' * 40
    tbl = f'<w:tbl><w:tblPr><w:tblW w:w="3000" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblBorders>{tb}</w:tblBorders><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid><w:gridCol w:w="3000"/></w:tblGrid>{rows}</w:tbl>'
    doc = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{tbl}<w:p/><w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>'
    with zipfile.ZipFile(OUT + name + ".docx", "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
        z.writestr("word/_rels/document.xml.rels", DOCRELS); z.writestr("word/document.xml", doc)
        z.writestr("word/styles.xml", STYLES); z.writestr("word/settings.xml", SETTINGS)
os.makedirs(OUT, exist_ok=True)
for sz in (2, 4, 8):
    for where in ("bottom", "top", "both"):
        build(f"c{where}-{sz}", "cell", where, sz)
    build(f"t-s{sz}", "tbl", None, sz)
print(sorted(os.listdir(OUT)))
