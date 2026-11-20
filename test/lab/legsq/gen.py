#!/usr/bin/env python3
"""Lab legsq (for amd-opus): does Word, in an older layout (compatibilityMode 12, compressPunctuation), squeeze a
line's marks to take a Latin piece (digits) past half a character over the margin? zh-eb54d3b0's line
"对年销售收入达到1000（含）—2000万元、2000（含）—5000…" takes "—5000" 24.7pt over in Word's print, each of its five
marks giving 4.9pt; the old rule allows only half a character. The document's own styles and settings, its line
as a paragraph of its own (from "对年销售收入" on, no first-line indent), the right indent stepped 0..60pt by 2pt.
Variants: A as is; B "五千" for the "5000" after the second dash; C "至" for that dash; D the "（含）" before it gone.
Read: for each paragraph (in order, 31 per variant), the text of its FIRST line in Word's print.
gen.py SRC.docx OUT.docx  (SRC = test/corpus/docx/docs/zh-eb54d3b0….docx)"""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode('utf-8')
para = [pm.group(0) for pm in re.finditer(r'<w:p[ >].*?</w:p>', doc, flags=re.S)
        if '对年销售收入达到1000' in ''.join(re.findall(r'<w:t[^>]*>([^<]*)', pm.group(0)))][0]
ppr = re.search(r'<w:pPr>.*?</w:pPr>', para, flags=re.S).group(0)
runs = re.findall(r'<w:r>.*?</w:r>', para, flags=re.S)
start = [i for i, r in enumerate(runs) if '对年销售收入' in r][0]
body_runs = runs[start:]
def variant(v):
    rs = list(body_runs)
    if v == 'B':
        rs = [r.replace('<w:t>5000万元、5000万元（含）</w:t>', '<w:t>五千万元、5000万元（含）</w:t>') for r in rs]
    if v == 'C':
        dashes = [i for i, r in enumerate(rs) if '<w:t>—</w:t>' in r]
        rs[dashes[1]] = rs[dashes[1]].replace('<w:t>—</w:t>', '<w:t>至</w:t>')
    if v == 'D':
        rs = [r.replace('<w:t>2000万元、2000（含）</w:t>', '<w:t>2000万元、2000多</w:t>') for r in rs]
    return ''.join(rs)
paras = []
for v in 'ABCD':
    for k in range(31):
        right = k * 40
        p = re.sub(r'<w:ind [^>]*/>', '<w:ind w:right="%d"/>' % right, ppr) if '<w:ind ' in ppr else ppr.replace('<w:pPr>', '<w:pPr><w:ind w:right="%d"/>' % right)
        paras.append('<w:p>%s%s</w:p>' % (p, variant(v)))
d = re.sub(r'(<w:body>).*(<w:sectPr)', lambda m: m.group(1) + ''.join(paras) + m.group(2), doc, count=1, flags=re.S)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zo:
    for n in z.namelist():
        zo.writestr(n, d.encode('utf-8') if n == 'word/document.xml' else z.read(n))
print(len(paras), 'paragraphs')
