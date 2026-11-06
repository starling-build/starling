#!/usr/bin/env python3
"""Lab hyph2 builder: how much overflow does Word tolerate for a hyphen-ended Latin piece at the line end? Room = piece width + delta, delta -3..+3 pt in 0.25 steps.
usage: build.py OUTDIR"""
import sys, os, zipfile
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DRELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>'
SETT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="{MODE}"/></w:compat></w:settings>'
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
def settings(mode): return SETT.replace("{MODE}", str(mode))
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
TXT = 9026                      # A4 text width in twips
NCJK = 15                       # CJK chars before the piece (157.5 pt)
TAIL = "文字文字文字文字文字文字文字"
PIECES = [("H", "S19-"), ("A", "S19-A")]
def rpr(fonts): return f'<w:rPr><w:rFonts {fonts}/><w:sz w:val="21"/></w:rPr>'
def para(text, fonts, jc, right):
    return (f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/><w:ind w:left="0" w:right="{right}"/><w:jc w:val="{jc}"/></w:pPr>'
            f'<w:r>{rpr(fonts)}<w:t xml:space="preserve">{text}</w:t></w:r></w:p>')
def label(t):
    return (f'<w:p><w:pPr><w:spacing w:before="120" w:after="0"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="14"/></w:rPr><w:t>{t}</w:t></w:r></w:p>')
SIM = 'w:ascii="SimSun" w:hAnsi="SimSun" w:eastAsia="SimSun"'
TNR = 'w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="SimSun"'
# base = width of "S19-" in twips: SimSun 4 x 5.25pt = 21pt; Times New Roman (0.556+0.5+0.5+0.333)em x 10.5 = 19.83pt
DOCS = [("1", "mode 12, SimSun, left", SIM, "left", 12, 420),
        ("2", "mode 12, Times New Roman Latin, left", TNR, "left", 12, 397),
        ("3", "mode 15, SimSun, left", SIM, "left", 15, 420),
        ("4", "mode 15, Times New Roman Latin, left", TNR, "left", 15, 397),
        ("5", "mode 12, SimSun, justified", SIM, "both", 12, 420)]
def build(out):
    for code, desc, fonts, jc, mode, base in DOCS:
        body = ""
        for key, piece in PIECES:
            for k in range(-12, 13):                # delta = k * 0.25 pt = k * 5 twips
                line = NCJK * 210 + base + 5 * k
                tag = f"{key}{'m' if k < 0 else 'p'}{abs(k) * 25:03d}"
                text = "中" * NCJK + piece + TAIL
                body += label(f"{tag}  [{piece}]") + para(text, fonts, jc, TXT - line)
        doc = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{body}'
               '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>')
        path = os.path.join(out, f"hyph2-{code}.docx")
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
            z.writestr("word/_rels/document.xml.rels", DRELS); z.writestr("word/document.xml", doc); z.writestr("word/settings.xml", settings(mode))
        print(path, "-", desc)
if __name__ == "__main__":
    os.makedirs(sys.argv[1], exist_ok=True); build(sys.argv[1])
