#!/usr/bin/env python3
"""Lab latg (Windows 01QbbApP, for amd-6, zh-08e95de4 p7): width of a Latin run in a linesAndChars grid.
A4, margins 90pt left/right (1800tw), top/bottom 1440; docDefaults sz 32 (16pt), ascii/hAnsi Times New Roman, eastAsia 仿宋; docGrid linesAndChars linePitch 590;
paragraph: jc both, spacing line 590 exact before/after 0, firstLine 0. No w:hint anywhere.
Six paragraphs a..f per doc: <N CJK><Latin><CJK filler>:
 a 26 CJK + R6   b 26 + R   c 25 + R6   d 24 + B1   e 26 + R6B1   f 27 + R
Docs: cs-1024 cs0 cs-2048 cs1024 (charSpace; linePitch unchanged) and snap0 (charSpace -1024 + <w:snapToGrid w:val="0"/> on every paragraph).
usage: build.py OUTDIR -> OUTDIR/latg-<doc>.docx (names: latgm1024, latg0, latgm2048, latgp1024, latgsnap0)"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
C = '一二三四五六七八九十甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午'   # 27, starts with 一, no repeats
FILL = '天地玄黄宇宙洪荒日月盈昃辰宿列张寒来暑往秋收冬藏闰余成岁律吕调阳'
VARS = [('a', 26, 'R6'), ('b', 26, 'R'), ('c', 25, 'R6'), ('d', 24, 'B1'), ('e', 26, 'R6B1'), ('f', 27, 'R')]
def para(n, lat, snap):
    s = '<w:snapToGrid w:val="0"/>' if snap == 0 else ''
    return (f'<w:p><w:pPr>{s}<w:spacing w:before="0" w:after="0" w:line="590" w:lineRule="exact"/><w:ind w:firstLine="0"/><w:jc w:val="both"/></w:pPr>'
            f'<w:r><w:t>{C[:n]}</w:t></w:r><w:r><w:t>{lat}</w:t></w:r><w:r><w:t>{FILL}</w:t></w:r></w:p>')
def doc(cs, snap):
    body = ''.join(para(n, lat, snap) for k, n, lat in VARS)
    sect = (f'<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1800" w:bottom="1440" w:left="1800" w:header="851" w:footer="992" w:gutter="0"/>'
            f'<w:docGrid w:type="linesAndChars" w:linePitch="590" w:charSpace="{cs}"/></w:sectPr>')
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{body}{sect}</w:body></w:document>'
DOCS = {'latgm1024': (-1024, 1), 'latg0': (0, 1), 'latgm2048': (-2048, 1), 'latgp1024': (1024, 1), 'latgsnap0': (-1024, 0)}
STYLES = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="仿宋"/>'
          '<w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr></w:rPrDefault><w:pPrDefault/></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>')
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DRELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
for k, (cs, snap) in DOCS.items():
    with zipfile.ZipFile(os.path.join(out, k + '.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS); z.writestr('word/document.xml', doc(cs, snap))
        z.writestr('word/styles.xml', STYLES); z.writestr('word/_rels/document.xml.rels', DRELS)
print(len(DOCS), 'docs')
