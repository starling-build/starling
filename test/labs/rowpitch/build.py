#!/usr/bin/env python3
"""Lab rowpitch (lenovo-3, for macos): the pitch of table rows in Word for Windows — why 317-twip rows with
0.25pt rules come out 16.08pt apart (321.6 twips) where ours are 16.10 (322), 0.7pt over 36 rows
(lo tdf152298).  Run from the repository root: python3 test/labs/rowpitch/build.py

Nine documents, each ONE table of 40 rows in one fixed column, a short "x" in each row (Times New Roman
12pt, single spacing, no space before/after, cell margins 0 top and bottom, page A4 margin 1134):
  r<rule>-<h>.docx   rule = s2 / s4 / none  (tblBorders single sz 2 = 0.25pt, sz 4 = 0.5pt, no borders)
                     h    = exact317 / atleast317 (w:trHeight 317 twips) / auto (no trHeight: the 12pt line)
Read with test/labs/rowpitch/meas.py DIR: per document the baseline y of each "x", the mean pitch of the 39
steps to 0.001pt, the spread (max-min), and the running total (last-first).  Question: is the pitch
height + rule, height + half the rule, or something Word quantises, at which unit?
"""
import os, zipfile
OUT = "test/labs/rowpitch/docx/"
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DOCRELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>'
SETTINGS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>'
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
STYLES = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {W}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>'
def build(name, rule, height):
    b = "" if rule == "none" else "".join(f'<w:{s} w:val="single" w:sz="{rule[1:]}" w:space="0" w:color="000000"/>' for s in ("top", "left", "bottom", "right", "insideH", "insideV"))
    tr = {"exact317": '<w:trPr><w:trHeight w:val="317" w:hRule="exact"/></w:trPr>',
          "atleast317": '<w:trPr><w:trHeight w:val="317" w:hRule="atLeast"/></w:trPr>', "auto": ""}[height]
    rows = f'<w:tr>{tr}<w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr><w:p><w:r><w:t>x</w:t></w:r></w:p></w:tc></w:tr>' * 40
    tbl = f'<w:tbl><w:tblPr><w:tblW w:w="3000" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblBorders>{b}</w:tblBorders><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid><w:gridCol w:w="3000"/></w:tblGrid>{rows}</w:tbl>'
    doc = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{tbl}<w:p/><w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>'
    with zipfile.ZipFile(OUT + name + ".docx", "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
        z.writestr("word/_rels/document.xml.rels", DOCRELS); z.writestr("word/document.xml", doc)
        z.writestr("word/styles.xml", STYLES); z.writestr("word/settings.xml", SETTINGS)
os.makedirs(OUT, exist_ok=True)
for rule in ("s2", "s4", "none"):
    for h in ("exact317", "atleast317", "auto"):
        build(f"r{rule}-{h}", rule, h)
print(sorted(os.listdir(OUT)))
