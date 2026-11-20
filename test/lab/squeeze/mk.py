#!/usr/bin/env python3
"""squeeze lab: real paragraph from zh-25381d22 (the line "），於國內各縣市約" in a 304.5 pt cell), repeated with the
right indent stepped 0.25 pt, one docx per variant. usage: mk.py <docs dir> <out dir>"""
import sys, glob, zipfile, os, re
docs, out = sys.argv[1:3]; os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(glob.glob(f"{docs}/zh-25381*.docx")[0]); pkg = {n: z.read(n) for n in z.namelist()}
d = pkg['word/document.xml'].decode()
i = d.find('於國內各縣市約'); j = max(d.rfind('<w:p ', 0, i), d.rfind('<w:p>', 0, i)); k = d.find('</w:p>', i) + 6
para = d[j:k]
def mk(name, ptx, steps, swap=None):
    body = ''
    for s in steps:   # s in quarter points: right indent = s*5 twips
        p = ptx if swap is None else swap(ptx)
        if '<w:ind ' in p: p = re.sub(r'<w:ind ([^>]*?)/>', lambda m: f'<w:ind {m.group(1)} w:right="{s*5}"/>', p, 1)
        else: p = p.replace('<w:pPr>', f'<w:pPr><w:ind w:right="{s*5}"/>', 1)
        body += p
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1000" w:right="856" w:bottom="1000" w:left="4482" w:header="0" w:footer="0" w:gutter="0"/></w:sectPr>'
    b0 = d.find('<w:body>') + 8
    nd = d[:b0] + body + sect + d[d.rfind('</w:body>'):]
    p2 = dict(pkg); p2['word/document.xml'] = nd.encode()
    with zipfile.ZipFile(f"{out}/{name}.docx", 'w', zipfile.ZIP_DEFLATED) as zz:
        for n, bt in p2.items(): zz.writestr(n, bt)
steps = list(range(-8, 41, 2))   # -2pt .. +10pt in 0.5pt
mk('q0-orig', para, steps)
mk('q1-comma-for-paren', para, steps, lambda p: p.replace('），於國內', '，，於國內'))
mk('q2-no-paren', para, steps, lambda p: p.replace('），於國內', '，於國內'))
