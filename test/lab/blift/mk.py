#!/usr/bin/env python3
"""blift lab: how far does a list bullet larger than its text lift the first line (xb fra-g210-1a6d33: a bold 12pt Calibri dash
over Arial 11, Word's items 0.26pt further apart than ours)? Package and compat from fra-g210-1a6d33. Each variant: a caption,
then three single-spaced items of Arial 11 with no paragraph spacing, then a plain line; the last variant again in a table cell.
usage: mk.py <xb docs dir> <out dir>"""
import sys, zipfile, glob, os, re
docs, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
p = glob.glob(f"{docs}/fra-g210-1a6d33*.docx")[0]
z = zipfile.ZipFile(p); pkg = {n: z.read(n) for n in z.namelist()}
d = pkg['word/document.xml'].decode()
b0 = d.find('<w:body>') + 8; sect = d[d.rfind('<w:sectPr'):d.rfind('</w:body>')]
V = [  # name, bullet rFonts face, bold, half-points
 ('calb12', 'Calibri', True, 24), ('cal12', 'Calibri', False, 24), ('calb14', 'Calibri', True, 28), ('calb16', 'Calibri', True, 32),
 ('arib12', 'Arial', True, 24), ('ari14', 'Arial', False, 28), ('tnr14', 'Times New Roman', False, 28), ('cal11', 'Calibri', False, 22),
]
n = pkg['word/numbering.xml'].decode()
absn, nums = '', ''
for k, (name, face, bold, sz) in enumerate(V):
    a = 900 + k
    absn += (f'<w:abstractNum w:abstractNumId="{a}"><w:multiLevelType w:val="hybridMultilevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/>'
             f'<w:numFmt w:val="bullet"/><w:lvlText w:val="-"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>'
             f'<w:rPr><w:rFonts w:ascii="{face}" w:hAnsi="{face}" w:cs="{face}" w:hint="default"/>{"<w:b/>" if bold else ""}'
             f'<w:sz w:val="{sz}"/><w:szCs w:val="{sz}"/></w:rPr></w:lvl></w:abstractNum>')
    nums += f'<w:num w:numId="{a}"><w:abstractNumId w:val="{a}"/></w:num>'
i = n.find('<w:num ')
n = n[:i] + absn + n[i:]
n = n.replace('</w:numbering>', nums + '</w:numbering>')
RPR = '<w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr>'
PPR = '<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/><w:ind w:left="720" w:hanging="360"/><w:contextualSpacing w:val="0"/><w:jc w:val="left"/>'
def par(t, num=None):
    np = f'<w:numPr><w:ilvl w:val="0"/><w:numId w:val="{num}"/></w:numPr>' if num else ''
    return f'<w:p><w:pPr><w:pStyle w:val="Normal"/>{np}{PPR}{RPR}</w:pPr><w:r>{RPR}<w:t xml:space="preserve">{t}</w:t></w:r></w:p>'
def group(k, name):
    return par(f'{name} Hx') + ''.join(par(f'Hx item {j}', 900 + k) for j in range(1, 4)) + par('Hx plain')
body = par('control Hx') + par('Hx plain') + par('Hx plain') + par('Hx plain')
for k, (name, *_) in enumerate(V): body += group(k, name)
cell = lambda c: f'<w:tc><w:tcPr><w:tcW w:w="4000" w:type="dxa"/></w:tcPr>{c}</w:tc>'
body += par('table calb12 Hx')
body += ('<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblBorders><w:top w:val="single" w:sz="4"/><w:left w:val="single" w:sz="4"/>'
         '<w:bottom w:val="single" w:sz="4"/><w:right w:val="single" w:sz="4"/><w:insideH w:val="single" w:sz="4"/><w:insideV w:val="single" w:sz="4"/></w:tblBorders>'
         '<w:tblLook w:val="04A0"/></w:tblPr><w:tblGrid><w:gridCol w:w="4000"/><w:gridCol w:w="4000"/></w:tblGrid>'
         '<w:tr>' + cell(''.join(par(f'Hx item {j}', 900) for j in range(1, 4))) + cell(''.join(par('Hx plain') for j in range(1, 4))) + '</w:tr></w:tbl>')
body += par('end Hx')
nd = d[:b0] + body + sect + d[d.rfind('</w:body>'):]
pk = dict(pkg); pk['word/document.xml'] = nd.encode(); pk['word/numbering.xml'] = n.encode()
with zipfile.ZipFile(f"{out}/blift.docx", 'w', zipfile.ZIP_DEFLATED) as zz:
    for nm, bb in pk.items(): zz.writestr(nm, bb)
print('ok')
