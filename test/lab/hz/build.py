#!/usr/bin/env python3
"""Lab hz (Windows 01QbbApP, for amd-5): 微軟正黑體 18pt heading "※壹、研究目的 ABC" baseline offset in a line=230/240 auto paragraph.
A4, margins 1440/1800. Docs hz0 (no docGrid) and hz1 (docGrid type=lines linePitch 360). Each doc: 16 variants x 2 contexts, one page each:
 key = <b|r>_<230|240>_<0|70>_<p|f> : bold/regular, line, spacing before (tw), p = heading is the 2nd paragraph (after a 12pt 新細明體 line 'PREV'), f = heading first on the page (pageBreakBefore)
Each page: [PREV line (p only)] heading, then a 12pt 新細明體 paragraph 'NEXT' (single, before 0).
usage: build.py OUTDIR -> hz0.docx hz1.docx cases.txt"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
HF = '<w:rFonts w:ascii="微軟正黑體" w:hAnsi="微軟正黑體" w:eastAsia="微軟正黑體" w:cs="微軟正黑體"/>'
BF = '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="新細明體"/>'
KEYS = [f'{b}_{ln}_{bf}_{c}' for b in 'br' for ln in (230, 240) for bf in (0, 70) for c in 'pf']
def para(text, rpr, ppr=''):
    return f'<w:p><w:pPr>{ppr}</w:pPr><w:r><w:rPr>{rpr}</w:rPr><w:t>{text}</w:t></w:r></w:p>'
def page(i, key):
    b, ln, bf, c = key.split('_')
    out = ''
    brk = '<w:pageBreakBefore/>' if True else ''
    if c == 'p':
        out += para(f'PREV {key}', BF + '<w:sz w:val="24"/>', brk + '<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>')
        hp = ''
    else:
        hp = brk
    out += para('※壹、研究目的 ABC', HF + ('<w:b/><w:bCs/>' if b == 'b' else '') + '<w:sz w:val="36"/><w:szCs w:val="36"/>',
                hp + f'<w:spacing w:before="{bf}" w:after="0" w:line="{ln}" w:lineRule="auto"/>')
    out += para('NEXT 下一段文字', BF + '<w:sz w:val="24"/>', '<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>')
    return out
BODY = ''.join(page(i, k) for i, k in enumerate(KEYS))
def doc(grid):
    g = '<w:docGrid w:type="lines" w:linePitch="360"/>' if grid else ''
    sect = f'<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1800" w:bottom="1440" w:left="1800" w:header="851" w:footer="992" w:gutter="0"/><w:cols w:space="425"/>{g}</w:sectPr>'
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{BODY}{sect}</w:body></w:document>'
STYLES = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr>{BF}<w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault/></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>'
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DR = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
DRELS = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="{DR}styles" Target="styles.xml"/><Relationship Id="rId2" Type="{DR}settings" Target="settings.xml"/></Relationships>'
SET = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {NS}><w:defaultTabStop w:val="480"/><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>'
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
for g in (0, 1):
    with zipfile.ZipFile(os.path.join(out, f'hz{g}.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS)
        z.writestr('word/document.xml', doc(g)); z.writestr('word/styles.xml', STYLES); z.writestr('word/settings.xml', SET)
        z.writestr('word/_rels/document.xml.rels', DRELS)
open(os.path.join(out, 'cases.txt'), 'w').write('\n'.join(KEYS) + '\n')
print(len(KEYS), 'pages per doc')
