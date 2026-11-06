#!/usr/bin/env python3
"""Lab hyph builder: where Word breaks a line at a hyphenated Latin piece (letter / digit / CJK after the hyphen) at the line end, mode 12, no grid.
usage: build.py OUTDIR"""
import sys, os, zipfile
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DRELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>'
SET = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="12"/></w:compat></w:settings>'
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
LINE = 4200            # twips: 210pt = 20 CJK chars of 10.5pt
RIGHT = 9026 - LINE    # A4, 1-inch margins
PIECES = [("A", "S19-A"), ("D", "S19-1"), ("C", "S19-中"), ("H", "S19-"), ("N", "S19A")]   # H: hyphen then CJK follows; N: control, no hyphen
TAIL = "文字文字文字文字文字文字文字"
def rpr(fonts):
    return f'<w:rPr><w:rFonts {fonts}/><w:sz w:val="21"/></w:rPr>'
def para(text, fonts, jc):
    return (f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/><w:ind w:left="0" w:right="{RIGHT}"/><w:jc w:val="{jc}"/></w:pPr>'
            f'<w:r>{rpr(fonts)}<w:t xml:space="preserve">{text}</w:t></w:r></w:p>')
def label(t):
    return (f'<w:p><w:pPr><w:spacing w:before="120" w:after="0"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="14"/></w:rPr><w:t>{t}</w:t></w:r></w:p>')
DOCS = [("1", "SimSun for both, left aligned", 'w:ascii="SimSun" w:hAnsi="SimSun" w:eastAsia="SimSun"', "left"),
        ("2", "SimSun for both, justified", 'w:ascii="SimSun" w:hAnsi="SimSun" w:eastAsia="SimSun"', "both"),
        ("3", "Times New Roman for Latin, SimSun for CJK, left aligned", 'w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="SimSun"', "left")]
def build(out):
    for code, desc, fonts, jc in DOCS:
        body = ""
        for key, piece in PIECES:
            for n in (15, 16, 17, 18, 19):          # CJK chars before the piece
                for m in (0, 1):                     # then m half-width digits "1"
                    text = "中" * n + "1" * m + piece + ("" if key in "C" else "") + TAIL
                    tag = f"{key}-{n:02d}-{m}"
                    body += label(f"{tag}  [{piece}]") + para(text, fonts, jc)
        doc = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{body}'
               '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>')
        path = os.path.join(out, f"hyph-{code}.docx")
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
            z.writestr("word/_rels/document.xml.rels", DRELS); z.writestr("word/document.xml", doc); z.writestr("word/settings.xml", SET)
        print(path, "-", desc)
if __name__ == "__main__":
    os.makedirs(sys.argv[1], exist_ok=True); build(sys.argv[1])
