#!/usr/bin/env python3
"""Lab nt1 (Windows 01QbbApP, for amd-7): how a nested table's cell padding repeats when a row splits over a page.
A4 (11906x16838), 36pt margins. outer (1 col, 1 row) > middle (1 col, 1 row) > inner (1 col, 1 row) with 75 lines "Line NN" (Arial 12, single spacing, one paragraph each).
The paragraph that Word needs after a nested table in a cell is a 1pt exact-height empty paragraph (sz 2), so it adds almost nothing.
usage: build.py OUTDIR
  nt1-0-control  no cell margins (all 0), no borders, at the page top
  nt1-A          all three levels tcMar top/bottom 113 twips, 0.5pt single borders top and bottom
  nt1-B          outer tcMar 0 + 0.5pt borders, middle tcMar 200 + 1.5pt borders, inner tcMar 60 + no borders
  nt1-C          as A, but the table starts 40pt above the page foot (an exact-height filler paragraph before it)
  nt1-Cc         as C and the control (no margins, no borders)"""
import sys, os, zipfile

W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
NLINES = 75


def para(text):
    return f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:t>{text}</w:t></w:r></w:p>'


TINY = '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/><w:rPr><w:sz w:val="2"/></w:rPr></w:pPr></w:p>'


def tc(inner, mar, bord, width):
    """mar = twips top/bottom; bord = border sz (eighths of a pt) or 0"""
    b = ''
    if bord:
        b = f'<w:tcBorders><w:top w:val="single" w:sz="{bord}" w:space="0" w:color="000000"/><w:bottom w:val="single" w:sz="{bord}" w:space="0" w:color="000000"/></w:tcBorders>'
    m = f'<w:tcMar><w:top w:w="{mar}" w:type="dxa"/><w:left w:w="0" w:type="dxa"/><w:bottom w:w="{mar}" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tcMar>'
    return f'<w:tc><w:tcPr><w:tcW w:w="{width}" w:type="dxa"/>{b}{m}</w:tcPr>{inner}</w:tc>'


def tbl(cell, width):
    return (f'<w:tbl><w:tblPr><w:tblW w:w="{width}" w:type="dxa"/><w:tblLayout w:type="fixed"/>'
            '<w:tblCellMar><w:left w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar></w:tblPr>'
            f'<w:tblGrid><w:gridCol w:w="{width}"/></w:tblGrid><w:tr>{cell}</w:tr></w:tbl>')


def nested(levels):
    """levels = [(mar, bord) outer, middle, inner]"""
    lines = ''.join(para(f"Line {i:02d}") for i in range(1, NLINES + 1))
    (mo, bo), (mm, bm), (mi, bi) = levels
    inner = tbl(tc(lines, mi, bi, 9800), 9800)
    middle = tbl(tc(inner + TINY, mm, bm, 9900), 9900)
    outer = tbl(tc(middle + TINY, mo, bo, 10000), 10000)
    return outer


CASES = {
    "nt1-0-control": ([(0, 0), (0, 0), (0, 0)], 0),
    "nt1-A": ([(113, 4), (113, 4), (113, 4)], 0),
    "nt1-B": ([(0, 4), (200, 12), (60, 0)], 0),
    "nt1-C": ([(113, 4), (113, 4), (113, 4)], 40),
    "nt1-Cc": ([(0, 0), (0, 0), (0, 0)], 40),
}


def build(path, levels, above_foot):
    body = ''
    if above_foot:
        # filler: the table starts 40pt above the foot (page 842 - 36 margin = 806): filler height = 806 - 40 - 36 = 730pt
        body += f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="{(842 - 36 - above_foot - 36) * 20}" w:lineRule="exact"/></w:pPr><w:r><w:t>filler</w:t></w:r></w:p>'
    body += nested(levels) + '<w:p/>'
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720" w:header="360" w:footer="360" w:gutter="0"/></w:sectPr>'
    document = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{body}{sect}</w:body></w:document>'
    styles = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {W}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="Arial" w:cs="Arial"/>'
              '<w:sz w:val="24"/><w:szCs w:val="24"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
              '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>')
    settings = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {W}><w:compat><w:compatSetting w:name="compatibilityMode" '
                'w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>')
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
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", ct)
        z.writestr("_rels/.rels", root)
        z.writestr("word/document.xml", document)
        z.writestr("word/styles.xml", styles)
        z.writestr("word/settings.xml", settings)
        z.writestr("word/_rels/document.xml.rels", drels)


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name, (levels, af) in CASES.items():
        build(os.path.join(out, name + ".docx"), levels, af)
        print(name)
