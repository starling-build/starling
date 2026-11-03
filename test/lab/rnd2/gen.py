#!/usr/bin/env python3
"""Lab rnd2 (for amd-opus), after lab rnd: where does Word for Windows' sub-unit shift at an
ideograph->digit space come from? Lab rnd's 12pt lines set every advance and space in whole
1/600in units, except "於1" (25.42 units, not 25) when 於 is the line's 17th character and 25.17
when it is the first. Rows a..q: k ideographs (k = 0..16, from "通過環境影響評估審查在案並分別") then
"於106年6月3日" — so the boundary moves along the line one cell at a time. Rows r, s: k = 16 with
"於" written "於A" (a letter, autoSpaceDE) and with the digits in 標楷體.
Earlier text, kept for reference: does Word for Windows snap each glyph's x to a device grid? zh-81aa310b
p2's line "通過環境影響評估審查在案，並分別於106年6月3日、106年6月7" prints its automatic spaces
3.05 ("於1") and 2.43 ("3日") where lab asz measured 3.00 and 2.40 — the line runs 0.05pt long,
and "及" is refused 0.03 over. Same package (zh-81aa310b), each line left-aligned, one per row,
in the body, nothing squeezed or stretched.
  a  the line as printed, 12pt                         (control: 3.05 / 2.43 again?)
  b  the line from "於" on only (the space now near the start)
  c-h the line, its left indent 1, 2, 3, 5, 8, 13 twips (the start moved by sub-point steps)
  i  10pt   j  10.5pt   k  11pt   l  14pt   m  16pt   (w:sz on every run)
  n  "於1於1於1於1於1於1於1於1" (eight ideograph->digit spaces, eight digit->ideograph)
  o  "於11於111於1111於11111於" (digit runs of growing length)
Read: for each row, line 1's per-character x origin and x1 (every character), and the line's
left edge (the paragraph's indent as Word reports it, if it can).
usage: gen.py CORPUS_DOCX_DIR OUTDIR"""
import sys, re, zipfile, os, glob
src_dir, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
z = zipfile.ZipFile(glob.glob(os.path.join(src_dir, 'zh-81aa310b*.docx'))[0])
doc = z.read('word/document.xml').decode('utf-8')
LINE = '通過環境影響評估審查在案，並分別於106年6月3日、106年6月7'
# The document's own run properties for that paragraph's text (its first run that holds "通過環境").
# (The paragraph holding "同意備查變更內容": its text is split across runs; its first run's rPr.)
k = doc.find('同意備查變更內容'); start = max(doc.rfind('<w:p>', 0, k), doc.rfind('<w:p ', 0, k))
rpr = re.search(r'<w:r[ >](?:(?!</w:r>).)*?(<w:rPr>.*?</w:rPr>)', doc[start:k], flags=re.S)
rpr = rpr and re.search(r'<w:rPr>.*?</w:rPr>', rpr.group(0), flags=re.S)
RPR = rpr.group(0) if rpr else '<w:rPr></w:rPr>'
RPR = re.sub(r'<w:(sz|szCs)\b[^>]*/>', '', RPR)
def para(text, ind=None, hp=None):
    rp = RPR if hp is None else RPR.replace('</w:rPr>', '<w:sz w:val="%d"/><w:szCs w:val="%d"/></w:rPr>' % (hp, hp))
    runs = ''.join('<w:r>%s<w:t>%s</w:t></w:r>' % (rp, piece) for piece in re.findall(r'[0-9]+|[^0-9]+', text))
    i = '' if ind is None else '<w:ind w:left="%d" w:firstLine="0"/>' % ind
    return '<w:p><w:pPr><w:jc w:val="left"/>%s<w:ind w:firstLine="0"/></w:pPr>%s</w:p>'.replace('<w:ind w:firstLine="0"/>', '' if i else '<w:ind w:left="0" w:firstLine="0"/>') % (i, runs)
PRE = '通過環境影響評估審查在案並分別'
rows = [(chr(ord('a') + k), para(PRE[:k] + '於106年6月3日')) for k in range(17)]
rows += [('r', para(PRE + '於A06年6月3日')), ('s', para(PRE + '於106年6月3日').replace('w:ascii="Times New Roman"', 'w:ascii="標楷體"').replace('w:hAnsi="Times New Roman"', 'w:hAnsi="標楷體"'))]
own = re.search(r'<w:sectPr[ >](?:(?!<w:sectPr[ >]).)*?</w:sectPr>\s*</w:body>', doc, flags=re.S).group(0)
own = re.sub(r'<w:(headerReference|footerReference)[^>]*/>', '', own)
body = ''.join(x for _, x in rows)
out = re.sub(r'(<w:body>).*(</w:body>)', lambda k: k.group(1) + body + own, doc, count=1, flags=re.S)
with zipfile.ZipFile(os.path.join(outdir, 'rnd2.docx'), 'w', zipfile.ZIP_DEFLATED) as zo:
    for n in z.namelist():
        zo.writestr(n, out.encode('utf-8') if n == 'word/document.xml' else z.read(n))
print('rnd2', ' '.join(k for k, _ in rows), RPR[:200])
