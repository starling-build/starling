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
    e = f(el); assert name.startswith(('v0','s00','f06')) or e != el, name
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

# ---- round 2: what decides refusal? (all at right indent 0 unless named) ----
def sw(a, b):
    assert el.count(a) == 1, a
    return lambda e: e.replace(a, b)
# fine right-indent sweep, -1.5..+1.0 pt in 0.25 steps (twips -30..+20 step 5): where does Word take 動?
for r in range(-30, 25, 5):
    mk(f'f{(r+30)//5:02d}-right{r}', lambda e, r=r: e.replace('<w:ind w:left="1800" w:hanging="1080"/>', f'<w:ind w:left="1800" w:right="{r}" w:hanging="1080"/>') if r else e)
# previous line's last char (中, which ends line 11 in Word) -> others, same width
for nm, ch in (('semi', '；'), ('dun', '、'), ('quote', '」'), ('plain', '市')):
    mk(f'p-prevlast-{nm}', sw('報案中心', f'報案{ch}心'))
# this line's first char (心) -> others
for nm, ch in (('plain', '市'), ('quote', '」'), ('semi', '；')):
    mk(f'q-first-{nm}', sw('報案中心', f'報案中{ch}'))
# line's last char E (動) -> others
for nm, ch in (('plain', '市'), ('quote', '」'), ('period', '。'), ('semi', '；')):
    mk(f'e-last-{nm}', sw('交通課；動物', f'交通課；{ch}物'))
# the mark before E (；) -> others
for nm, ch in (('comma', '，'), ('plain', '市'), ('period', '。')):
    mk(f'm-mark-{nm}', sw('交通課；動物', f'交通課{ch}動物'))
print(sorted(os.listdir(out)))
