#!/usr/bin/env python3
"""Lab nt (Windows 01QbbApP, for amd-5): where does the text start after a multilevel number whose end is near the hanging position?
A4, left margin 1800tw, default tab 480, 13pt 標楷體 body, number 14pt (as zh-12c4f07a lvl 3: sz 28 -> digits 7.0pt, number 63.0). Each case = one paragraph "乙方承諾" with its own w:num (startOverride 3,3,2,10 -> "3.3.2.10.") at ilvl 3,
ind left=2154 hanging=H. Cases (key: hanging, extra):
 a1280 a1262 a1260 a1258 a1240            suff=tab
 b1280 ..b1240                            + explicit tab stop at 2154
 c1280 ..c1240                            suff=space
 d1260                                    number "3.3.2.1." (one digit shorter)
 e1260                                    list font Times New Roman 12pt
usage: build.py OUTDIR -> nt15.docx (compatibilityMode 15), nt14.docx (14), cases.txt"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
H = [1280, 1262, 1260, 1258, 1240]
CASES = [(f'{k}{h}', h, k) for k in 'abc' for h in H] + [('d1260', 1260, 'd'), ('e1260', 1260, 'e')]
FACE = '<w:rFonts w:ascii="標楷體" w:hAnsi="標楷體" w:eastAsia="標楷體" w:cs="Times New Roman"/>'
TNR = '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="Times New Roman" w:cs="Times New Roman"/>'
def abstract(i, k):
    suff = '<w:suff w:val="space"/>' if k == 'c' else ''
    rpr = (TNR + '<w:sz w:val="24"/>') if k == 'e' else (FACE + '<w:sz w:val="28"/>')
    st = [3, 3, 2, 1 if k == 'd' else 10]
    lv = ''
    for l in range(4):
        lt = '.'.join('%%%d' % (j + 1) for j in range(l + 1)) + '.'
        lv += f'<w:lvl w:ilvl="{l}"><w:start w:val="{st[l]}"/><w:numFmt w:val="decimal"/>{suff}<w:lvlText w:val="{lt}"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="{2154}" w:hanging="1260"/></w:pPr><w:rPr>{rpr}</w:rPr></w:lvl>'
    return f'<w:abstractNum w:abstractNumId="{i}"><w:multiLevelType w:val="multilevel"/>{lv}</w:abstractNum>'
NUM = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:numbering {NS}>' + ''.join(abstract(i, c[2]) for i, c in enumerate(CASES)) + ''.join(f'<w:num w:numId="{i + 1}"><w:abstractNumId w:val="{i}"/></w:num>' for i in range(len(CASES))) + '</w:numbering>'
def para(i, h, k):
    tabs = '<w:tabs><w:tab w:val="num" w:pos="2154"/></w:tabs>' if k == 'b' else ''
    ppr = f'<w:pPr><w:numPr><w:ilvl w:val="3"/><w:numId w:val="{i + 1}"/></w:numPr>{tabs}<w:spacing w:before="0" w:after="360"/><w:ind w:left="2154" w:hanging="{h}"/></w:pPr>'
    return f'<w:p>{ppr}<w:r><w:t>乙方承諾</w:t></w:r></w:p>'
BODY = ''.join(para(i, h, k) for i, (key, h, k) in enumerate(CASES))
def doc():
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1800" w:bottom="1440" w:left="1800" w:header="851" w:footer="992" w:gutter="0"/><w:cols w:space="425"/></w:sectPr>'
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{BODY}{sect}</w:body></w:document>'
STYLES = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr>{FACE}<w:sz w:val="26"/><w:szCs w:val="26"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>'
def settings(m): return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {NS}><w:defaultTabStop w:val="480"/><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="{m}"/></w:compat></w:settings>'
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DR = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
DRELS = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="{DR}styles" Target="styles.xml"/><Relationship Id="rId2" Type="{DR}settings" Target="settings.xml"/><Relationship Id="rId3" Type="{DR}numbering" Target="numbering.xml"/></Relationships>'
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
for m in (15, 14):
    with zipfile.ZipFile(os.path.join(out, f'nt{m}.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS)
        z.writestr('word/document.xml', doc()); z.writestr('word/styles.xml', STYLES); z.writestr('word/settings.xml', settings(m))
        z.writestr('word/numbering.xml', NUM); z.writestr('word/_rels/document.xml.rels', DRELS)
open(os.path.join(out, 'cases.txt'), 'w', encoding='utf-8').write('\n'.join(c[0] for c in CASES) + '\n')
print(len(CASES), 'cases')
