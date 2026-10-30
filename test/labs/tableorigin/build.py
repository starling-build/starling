#!/usr/bin/env python3
"""Lab tableorigin (lenovo-3, for macos): where the left edge of a table stands in Word for Windows by the
file's compatibility state and view (lo tdf96749: no compat settings and <w:view w:val="web"/>; Word's first inner
rule is at x 43.4 = margin 28.35 + the 15.75pt first column - 0.7, ours 38.6 = margin + 15.75 - 5.4; lab gridcells
puts the left rule AT the margin, x 28.56, in mode 15).  Run from the repository root:
python3 test/labs/tableorigin/build.py

Eight documents, each ONE row of four cells (A B C D, 2400 twips each, grid equal), single 0.5pt rules, tblW auto,
autofit, no tblInd, cell margins from the defaults (none stated), a marker line "M" above, A4 margins 567:
  o-<state>[-web].docx   state = none (no w:compat at all) / m12 / m14 / m15 (compatibilityMode); "-web" adds
                         <w:view w:val="web"/> to the settings.
Read with test/labs/tableorigin/meas.py DIR: the x of the table's leftmost and rightmost vertical rule and of the
letters A..D.  Question: in which state does the table's left rule stand at the margin (28.35 + 0.2), at the
margin less the cell margin, or at margin - 0.7?
"""
import os, zipfile
OUT = "test/labs/tableorigin/docx/"
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DOCRELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>'
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
STYLES = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {W}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>'
def settings(state, web):
    v = '<w:view w:val="web"/>' if web else ""
    c = "" if state == "none" else f'<w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="{state[1:]}"/></w:compat>'
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {W}>{v}<w:zoom w:percent="100"/>{c}</w:settings>'
def build(name, state, web):
    borders = "".join(f'<w:{s} w:val="single" w:sz="4" w:space="0" w:color="000000"/>' for s in ("top", "left", "bottom", "right", "insideH", "insideV"))
    cols = "".join('<w:gridCol w:w="2400"/>' for _ in range(4))
    cells = "".join(f'<w:tc><w:tcPr><w:tcW w:w="2400" w:type="dxa"/></w:tcPr><w:p><w:r><w:t>{c}</w:t></w:r></w:p></w:tc>' for c in "ABCD")
    tbl = f'<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblBorders>{borders}</w:tblBorders><w:tblLayout w:type="autofit"/></w:tblPr><w:tblGrid>{cols}</w:tblGrid><w:tr>{cells}</w:tr></w:tbl>'
    doc = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body><w:p><w:r><w:t>M</w:t></w:r></w:p>{tbl}<w:p/><w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="567" w:bottom="1134" w:left="567" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>'
    with zipfile.ZipFile(OUT + name + ".docx", "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
        z.writestr("word/_rels/document.xml.rels", DOCRELS); z.writestr("word/document.xml", doc)
        z.writestr("word/styles.xml", STYLES); z.writestr("word/settings.xml", settings(state, web))
os.makedirs(OUT, exist_ok=True)
for state in ("none", "m12", "m14", "m15"):
    for web in (False, True):
        build(f"o-{state}" + ("-web" if web else ""), state, web)
print(sorted(os.listdir(OUT)))
