#!/usr/bin/env python3
"""semi lab: zh-ea70c30e's real paragraph, one change per variant. Word wraps "動" at the end of "…警察服務 – 交通課；"
where we squeeze four ； to pull it in. Print each; compare which line "動" starts.
usage: mk.py <docs dir> <out dir>"""
import sys, zipfile, glob, os
docs, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
p = glob.glob(f"{docs}/zh-ea70c30e*.docx")[0]; z = zipfile.ZipFile(p); pkg = {n: z.read(n) for n in z.namelist()}
d = pkg['word/document.xml'].decode()
i = d.find('「第一層級部門」是指'); j = max(d.rfind('<w:p ', 0, i), d.rfind('<w:p>', 0, i)); k = d.find('</w:p>', i) + 6
el = d[j:k]; b0 = d.find('<w:body>') + 8; sect = d[d.rfind('<w:sectPr'):d.rfind('</w:body>')]
def mk(name, f):
    e = f(el); assert name.startswith(('v0','s00')) or e != el, name
    nd = d[:b0] + e + sect + d[d.rfind('</w:body>'):]
    pk = dict(pkg); pk['word/document.xml'] = nd.encode()
    with zipfile.ZipFile(f"{out}/{name}.docx", 'w', zipfile.ZIP_DEFLATED) as zz:
        for n, b in pk.items(): zz.writestr(n, b)
mk('v0-base', lambda e: e)
mk('v1-no-adjustRightInd', lambda e: e.replace('<w:adjustRightInd w:val="0"/>', ''))
mk('v2-no-autoSpace', lambda e: e.replace('<w:autoSpaceDE w:val="0"/>', '').replace('<w:autoSpaceDN w:val="0"/>', ''))
mk('v3-semicolon-to-comma', lambda e: e.replace('；', '，'))
mk('v4-left-aligned', lambda e: e.replace('<w:jc w:val="both"/>', '<w:jc w:val="left"/>'))
mk('v5-space-runs-merged-hint', lambda e: e.replace('<w:rFonts w:ascii="PMingLiU" w:cs="PMingLiU"/>', '<w:rFonts w:ascii="PMingLiU" w:cs="PMingLiU" w:hint="eastAsia"/>'))
# right-indent sweep (twips, 20 = 1pt): does Word take 動 at some width, and where does the line flip?
for r in range(0, 260, 20):
    mk(f's{r//20:02d}-right{r}', lambda e, r=r: e.replace('<w:ind w:left="1800" w:hanging="1080"/>', f'<w:ind w:left="1800" w:right="{r}" w:hanging="1080"/>') if r else e)
print(sorted(os.listdir(out)))
