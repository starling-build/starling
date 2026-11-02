#!/usr/bin/env python3
"""Lab ovfit builder: how Word shrinks an AUTOFIT table whose grid is wider than the text area. usage: build.py OUTDIR"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
W = 9360  # text width, twips (Letter, 1in margins)
LONG = "Zusatzliche Technische Vertragsbedingungen Vorschriften und Richtlinien fur Strassenbauarbeiten in Dresden"
#  code, description, grid twips, indent twips, per-cell text list, width-of-page-text-used
V = [
 ("A1", "doc's grid 616/2150/4936/2023 (4% over), short words",        [616,2150,4936,2023], 0,   ["c1","c2","c3","c4"]),
 ("A2", "same grid, long wrapping text in column 3",                    [616,2150,4936,2023], 0,   ["c1","c2 TR Stra Dresden",LONG,"c4 Fassung 2011"]),
 ("A3", "same as A2 with table indent 124",                             [616,2150,4936,2023], 124, ["c1","c2 TR Stra Dresden",LONG,"c4 Fassung 2011"]),
 ("A4", "five equal columns 2000 each (7% over), short words",          [2000]*5,             0,   ["c1","c2","c3","c4","c5"]),
 ("A5", "grid 1200/3600/6000 (15% over), short words",                  [1200,3600,6000],     0,   ["c1","c2","c3"]),
 ("A6", "four equal columns 3000 each (28% over), short words",         [3000]*4,             0,   ["c1","c2","c3","c4"]),
 ("A7", "A6 with an unbreakable 30-char word in column 1",              [3000]*4,             0,   ["c1 WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW","c2","c3","c4"]),
 ("A8", "A6 with an unbreakable 30-char word in column 4",              [3000]*4,             0,   ["c1","c2","c3","c4 WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"]),
 ("A9", "grid 600/6000/6000 (35% over), column 1 a short word",         [600,6000,6000],      0,   ["c1","c2","c3"]),
 ("A10","A6 but the table says tblW auto, tcW 3000 each and NO grid shrink: control fixed layout", [3000]*4, 0, ["c1","c2","c3","c4"]),
]
def cell(w, t): return f'<w:tc><w:tcPr><w:tcW w:w="{w}" w:type="dxa"/></w:tcPr><w:p><w:r><w:t xml:space="preserve">{t}</w:t></w:r></w:p></w:tc>'
def doc(code, grid, ind, texts):
    fixed = '<w:tblLayout w:type="fixed"/>' if code == "A10" else ''
    indx = f'<w:tblInd w:w="{ind}" w:type="dxa"/>' if ind else ''
    tbl = (f'<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/>{indx}{fixed}<w:tblCellMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr>'
           '<w:tblGrid>' + ''.join(f'<w:gridCol w:w="{g}"/>' for g in grid) + '</w:tblGrid><w:tr>'
           + ''.join(cell(g, t) for g, t in zip(grid, texts)) + '</w:tr></w:tbl>')
    sect = '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{tbl}<w:p/>{sect}</w:body></w:document>'
STYLES = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="20"/></w:rPr></w:rPrDefault>'
          '<w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>')
SETTINGS = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {NS}><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>')
CT = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
DRELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
def main(out):
    os.makedirs(out, exist_ok=True)
    for n, (code, desc, grid, ind, texts) in enumerate(V, 1):
        with zipfile.ZipFile(os.path.join(out, f"ovfit-{n:02d}-{code}.docx"), "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
            z.writestr("word/document.xml", doc(code, grid, ind, texts)); z.writestr("word/styles.xml", STYLES)
            z.writestr("word/settings.xml", SETTINGS); z.writestr("word/_rels/document.xml.rels", DRELS)
    print(len(V), "documents in", out)
if __name__ == "__main__": main(sys.argv[1])
