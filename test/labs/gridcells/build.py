#!/usr/bin/env python3
"""Lab gridcells (lenovo-3, for macos): where Word for Windows places an autofit table whose tblGrid is wider (or
narrower) than its cells' widths, centred or left, with and without tblInd (lo tdf96749: Word's table is centred
by its CELL widths, 506.8pt, in a grid of 522.4pt; ours stands 5.7pt left of that).  Run from the repository
root: python3 test/labs/gridcells/build.py

Page A4, margins 567 twips (text width 10773 twips = 538.65pt, x from 28.35 to 567.0).  One table of one row and
four cells, a letter "A".."D" in each, single 0.5pt rules (tblBorders sz 4), tblW auto, tblLayout autofit
unless the name says fixed, tblCellMar 108 left/right, cell widths 2400 twips each (9600 = 480pt).
  g1-equal            grid 2400 x4 (= cells)
  g2-gridwider        grid 2500 x4 (10000), cells 2400
  g3-gridnarrower     grid 2300 x4 (9200), cells 2400
  g4-equal-ind300     as g1, tblInd 300
  g5-gridwider-ind300 as g2, tblInd 300
  g6-equal-center     as g1, tblPr jc center
  g7-gridwider-center as g2, jc center
  g8-gridwider-fixed  as g2, tblLayout fixed
  g9-gridwider-spanned as g2 with ONE row of one cell tcW 9600 gridSpan 4 (cells not matching the grid's columns)
Read with test/labs/gridcells/meas.py DIR: per document the x of the table's leftmost and rightmost vertical
rule and the x of each letter.  Question: left = margin - 5.4 + indent, from the grid or from the cells?  centred
= over the grid's width or the cells'?
"""
import os, zipfile
OUT = "test/labs/gridcells/docx/"
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DOCRELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>'
SETTINGS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>'
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
STYLES = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {W}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>'
def build(name, grid, ind=None, jc=None, layout="autofit", spanned=False):
    borders = "".join(f'<w:{s} w:val="single" w:sz="4" w:space="0" w:color="000000"/>' for s in ("top", "left", "bottom", "right", "insideH", "insideV"))
    pr = f'<w:tblW w:w="0" w:type="auto"/>' + (f'<w:jc w:val="{jc}"/>' if jc else "") + (f'<w:tblInd w:w="{ind}" w:type="dxa"/>' if ind else "") \
        + f'<w:tblBorders>{borders}</w:tblBorders><w:tblLayout w:type="{layout}"/><w:tblCellMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar>'
    cols = "".join(f'<w:gridCol w:w="{grid}"/>' for _ in range(4))
    if spanned:
        cells = '<w:tc><w:tcPr><w:tcW w:w="9600" w:type="dxa"/><w:gridSpan w:val="4"/></w:tcPr><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc>'
    else:
        cells = "".join(f'<w:tc><w:tcPr><w:tcW w:w="2400" w:type="dxa"/></w:tcPr><w:p><w:r><w:t>{c}</w:t></w:r></w:p></w:tc>' for c in "ABCD")
    tbl = f'<w:tbl><w:tblPr>{pr}</w:tblPr><w:tblGrid>{cols}</w:tblGrid><w:tr>{cells}</w:tr></w:tbl>'
    doc = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body><w:p><w:r><w:t>M</w:t></w:r></w:p>{tbl}<w:p/><w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="567" w:bottom="1134" w:left="567" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>'
    with zipfile.ZipFile(OUT + name + ".docx", "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
        z.writestr("word/_rels/document.xml.rels", DOCRELS); z.writestr("word/document.xml", doc)
        z.writestr("word/styles.xml", STYLES); z.writestr("word/settings.xml", SETTINGS)
os.makedirs(OUT, exist_ok=True)
build("g1-equal", 2400); build("g2-gridwider", 2500); build("g3-gridnarrower", 2300)
build("g4-equal-ind300", 2400, ind=300); build("g5-gridwider-ind300", 2500, ind=300)
build("g6-equal-center", 2400, jc="center"); build("g7-gridwider-center", 2500, jc="center")
build("g8-gridwider-fixed", 2500, layout="fixed"); build("g9-gridwider-spanned", 2500, spanned=True)
print(sorted(os.listdir(OUT)))
