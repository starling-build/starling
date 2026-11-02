#!/usr/bin/env python3
"""Lab cbcol builder: how narrow does Word make an overfull table's check-box column, and does tblInd narrow the room? usage: build.py OUTDIR"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
CHK = ('<w:r><w:fldChar w:fldCharType="begin"><w:ffData><w:name w:val=""/><w:enabled/><w:calcOnExit w:val="0"/><w:checkBox>{size}<w:checked/></w:checkBox></w:ffData></w:fldChar></w:r>'
       '<w:r><w:instrText> FORMCHECKBOX </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r>')
GRID = (616, 2150, 4936, 2023)          # the corpus table: 9725 twips against a 9071 text width
SMALL = (616, 2150, 4000, 2023)         # 8789: fits, nothing to shrink
#  code, grid, tblInd twips, first-column content: chk / chk22 / empty / X / MMMMMM / MMMMMMMMMM
V = [("orig-chk-ind124", GRID, 124, "chk"), ("chk-ind0", GRID, 0, "chk"), ("chk-ind300", GRID, 300, "chk"),
     ("empty-ind124", GRID, 124, "empty"), ("empty-ind0", GRID, 0, "empty"), ("X-ind0", GRID, 0, "X"),
     ("M6-ind0", GRID, 0, "M6"), ("M6-ind124", GRID, 124, "M6"), ("M10-ind0", GRID, 0, "M10"),
     ("chk22-ind0", GRID, 0, "chk22"), ("chk-fits-ind124", SMALL, 124, "chk"), ("chk-fits-ind0", SMALL, 0, "chk")]
def first(kind):
    sp = '<w:pPr><w:spacing w:before="0" w:after="0"/><w:jc w:val="center"/></w:pPr>'
    if kind == "chk": return f'<w:p>{sp}{CHK.format(size="<w:sizeAuto/>")}</w:p>'
    if kind == "chk22": return f'<w:p>{sp}{CHK.format(size=chr(60)+"w:size w:val="+chr(34)+"22"+chr(34)+"/>")}</w:p>'
    if kind == "empty": return '<w:p/>'
    txt = {"X": "X", "M6": "MMMMMM", "M10": "MMMMMMMMMM"}[kind]
    return f'<w:p>{sp}<w:r><w:t>{txt}</w:t></w:r></w:p>'
def cell(w, inner):
    return f'<w:tc><w:tcPr><w:tcW w:type="dxa" w:w="{w}"/></w:tcPr>{inner}</w:tc>'
def t(s, b=False):
    return f'<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr><w:r><w:rPr>{"<w:b/>" if b else ""}</w:rPr><w:t>{s}</w:t></w:r></w:p>'
def doc(grid, ind, kind):
    bd = ''.join(f'<w:{e} w:val="single" w:sz="4" w:space="0" w:color="000000"/>' for e in ("top", "left", "bottom", "right", "insideH", "insideV"))
    rows = ''
    for r in range(2):
        rows += '<w:tr>' + cell(grid[0], first(kind)) + cell(grid[1], t("TR Stra Dresden", True)) + cell(grid[2], t("Technisches Regelwerk für Straßenbauarbeiten in Dresden")) + cell(grid[3], t("Fassung 2011")) + '</w:tr>'
    tbl = (f'<w:tbl><w:tblPr><w:jc w:val="left"/><w:tblInd w:type="dxa" w:w="{ind}"/><w:tblBorders>{bd}</w:tblBorders>'
           '<w:tblCellMar><w:left w:type="dxa" w:w="108"/><w:right w:type="dxa" w:w="108"/></w:tblCellMar></w:tblPr><w:tblGrid>' + ''.join(f'<w:gridCol w:w="{g}"/>' for g in grid) + f'</w:tblGrid>{rows}</w:tbl>')
    sect = '<w:sectPr><w:pgSz w:h="16838" w:w="11906"/><w:pgMar w:bottom="1134" w:footer="709" w:gutter="0" w:header="709" w:left="1701" w:right="1134" w:top="1701"/></w:sectPr>'
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{tbl}<w:p/>{sect}</w:body></w:document>'
STYLES = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="22"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>')
CT = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
DRELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>')
def main(out):
    os.makedirs(out, exist_ok=True)
    for n, (code, grid, ind, kind) in enumerate(V, 1):
        with zipfile.ZipFile(os.path.join(out, f"cbcol-{n:02d}-{code}.docx"), "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
            z.writestr("word/document.xml", doc(grid, ind, kind)); z.writestr("word/styles.xml", STYLES)
            z.writestr("word/_rels/document.xml.rels", DRELS)
    print(len(V), "documents in", out)
if __name__ == "__main__": main(sys.argv[1])
