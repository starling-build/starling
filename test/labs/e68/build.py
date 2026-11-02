#!/usr/bin/env python3
"""Lab e68 (for amd-opus/windows): how far past the margin does Word for Windows take the digit "4" of
"……最小间距按表4—1控制。" at a line's end by squeezing the "）" of the opening "（一）"?
zh-e68a2f57's own first paragraph (mode 14, SimSun 16pt, exact 29pt lines, first-line indent 32pt, compressPunctuation),
copied with its own section; the right indent is stepped so the "4" ends T pt past the margin, T = -1.0 .. 5.0 in
0.2pt steps (31 paragraphs per variant; right = T - 1.8 pt, 1.8 being what ours measures over at right indent 0;
negative indents are intended). In Word's print of the document the "4" is NOT taken (the line ends "…按表").
Variants (one file each):
  a   as the document is:        "…间距按表4—1控制。"
  b   no dash:                    "…间距按表4控制。"       (the digit followed by an ideograph)
  c   ASCII hyphen:               "…间距按表4-1控制。"
  d   as a, a second mark earlier: "（一）住宅建筑，各类朝向平行相对布置时最小间距按表4—1控制。" (the "的" gone so the "4" sits where it did)
Read: for each paragraph in order (T = -1.0 + 0.2*k), does Word's first line end with the "4" (digit taken) or with "表"
(digit sent down, with or without the dash)? The T at which it flips from taken to down is Word's limit.
build.py SRC.docx OUTDIR   (SRC = test/corpus/docx/docs/zh-e68a2f57*.docx)"""
import sys, re, zipfile, os
src, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode('utf-8')
text = lambda s: ''.join(re.findall(r'<w:t[^>]*>([^<]*)', s))
paras = list(re.finditer(r'<w:p[ >](?:(?!<w:p[ >]).)*?</w:p>', doc, flags=re.S))
para = [m.group(0) for m in paras if '（一）住宅建筑各类朝向' in text(m.group(0))][0]
m = re.match(r'(<w:p[^>]*>)(<w:pPr>.*?</w:pPr>)?(.*)</w:p>$', para, flags=re.S)
ppr, body0 = m.group(2), m.group(3)
def variant(name):
    b = body0
    if name == 'b':
        b = b.replace('<w:t>—</w:t>', '<w:t></w:t>', 1).replace('<w:t>1控制。</w:t>', '<w:t>控制。</w:t>', 1)
    if name == 'c':
        b = b.replace('<w:t>—</w:t>', '<w:t>-</w:t>', 1)
    if name == 'd':
        b = b.replace('住宅建筑各类朝向平行相对布置时的最小', '住宅建筑，各类朝向平行相对布置时最小', 1)
    assert b != body0 or name == 'a'
    return b
own = re.search(r'<w:sectPr[ >].*?</w:sectPr>', doc[doc.index(para):], flags=re.S).group(0)
for name in 'abcd':
    body = variant(name)
    ps = []
    for k in range(31):
        T = -1.0 + 0.2 * k
        right = round((T - 1.8) * 20)
        p = ppr.replace('<w:ind w:firstLine="640"', '<w:ind w:right="%d" w:firstLine="640"' % right, 1)
        assert 'w:right=' in p
        ps.append('<w:p>%s%s</w:p>' % (p, body))
    d = re.sub(r'(<w:body>).*(</w:body>)', lambda k: k.group(1) + ''.join(ps) + own + k.group(2), doc, count=1, flags=re.S)
    path = os.path.join(outdir, 'e68-%s.docx' % name)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in z.namelist():
            zo.writestr(n, d.encode('utf-8') if n == 'word/document.xml' else z.read(n))
    print(name, len(ps), 'paragraphs ->', path)
