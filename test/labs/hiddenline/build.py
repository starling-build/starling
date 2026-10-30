#!/usr/bin/env python3
"""Lab hiddenline (lenovo-3, for macos): what line height does Word for Windows give a paragraph whose
text is all hidden, all deleted (tracked), or both, with a normal, hidden or deleted paragraph mark,
at 10, 12 and 16pt?  Run from the repository root: python3 test/labs/hiddenline/build.py

Each document is a column of visible marker paragraphs "M01 ...", "M02 ..." with ONE test paragraph
between consecutive markers.  Read, in each print, the y of each marker's baseline; the test
paragraph's height is (next marker y) - (this marker y) - (a visible line's pitch), the pitch being
taken from the control rows.  Spacing after is 0 and line spacing single throughout (Arial).

  S<size>-all.docx     tracked changes present (the print is a markup page, scaled): every test row below
  S<size>-hidden.docx  hidden-only rows, no tracked change in the file (a plain page)
Rows ("text" / "mark"):  text h = vanish, d = tracked deletion, hd = both, v = visible, e = no run at all;
mark n = ordinary, h = hidden (w:vanish), d = tracked deletion.
"""
import os, zipfile

OUT = "test/labs/hiddenline/docx/"
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DOCRELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>'
SETTINGS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>'
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
def styles(size):
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {W}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="{size*2}"/><w:szCs w:val="{size*2}"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>'
AU = 'w:id="{i}" w:author="lab" w:date="2026-01-01T00:00:00Z"'
def para(text, mark, n):
    mk = {"n": "", "h": "<w:vanish/>", "d": f'<w:del {AU.format(i=100+n)}/>'}[mark]
    ppr = f"<w:pPr><w:rPr>{mk}</w:rPr></w:pPr>" if mk else ""
    if text == "e": runs = ""
    elif text == "v": runs = "<w:r><w:t>xyz</w:t></w:r>"
    elif text == "h": runs = "<w:r><w:rPr><w:vanish/></w:rPr><w:t>xyz</w:t></w:r>"
    elif text == "d": runs = f'<w:del {AU.format(i=200+n)}><w:r><w:delText>xyz</w:delText></w:r></w:del>'
    elif text == "hd": runs = f'<w:del {AU.format(i=200+n)}><w:r><w:rPr><w:vanish/></w:rPr><w:delText>xyz</w:delText></w:r></w:del>'
    return f"<w:p>{ppr}{runs}</w:p>"
ALL = [("v","n"),("e","n"),("e","h"),("e","d"),("v","d"),("h","n"),("h","h"),("h","d"),("d","n"),("d","h"),("d","d"),("hd","n"),("hd","h"),("hd","d")]
HIDDEN = [("v","n"),("e","n"),("e","h"),("h","n"),("h","h")]
def build(name, size, rows):
    body = ""
    for k, (t, m) in enumerate(rows, 1):
        body += f'<w:p><w:r><w:t>M{k:02d} text={t} mark={m}</w:t></w:r></w:p>' + para(t, m, k)
    body += f'<w:p><w:r><w:t>M{len(rows)+1:02d} end</w:t></w:r></w:p>'
    doc = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{body}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>'
    with zipfile.ZipFile(OUT + name + ".docx", "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
        z.writestr("word/_rels/document.xml.rels", DOCRELS); z.writestr("word/document.xml", doc)
        z.writestr("word/styles.xml", styles(size)); z.writestr("word/settings.xml", SETTINGS)
os.makedirs(OUT, exist_ok=True)
for size in (10, 12, 16):
    build(f"S{size}-all", size, ALL)
    build(f"S{size}-hidden", size, HIDDEN)
print(sorted(os.listdir(OUT)))
