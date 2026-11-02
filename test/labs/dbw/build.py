#!/usr/bin/env python3
"""Lab dbw (for amd-opus/windows): where does Word for Windows stop taking a Latin piece "DB" at a line's end,
and how much do the line's word spaces weigh? zh-cd8987db's own paragraph ("DB 5308/T 57-2020 界定的以及…，以下
重复列出了DB 5308/T 43-2021…", mode 15, SimSun 10.5pt, compressPunctuation, balance on, justified, first-line indent
420), copied with its own section and the right indent stepped so the "DB" at the end of its first line walks
from 1.0 to 12.0pt past the margin in 0.2pt steps (56 paragraphs per variant; right = (T + removed - 4.8) pt, 4.8
being what ours measures over at indent 0, `removed` the width Word set the removed spaces at: 3.96, 3.84, 5.16).
Variants (one file each):
  sp3   as the document is (three word spaces on the line: "DB 5308/T 57-2020 界定")
  sp1   the two Latin spaces removed ("DB5308/T57-2020 界定"), one left
  sp0   all three removed ("DB5308/T57-2020界定")
  ideo  as sp3, the final "DB" an ideograph "库" (the candidate no longer Latin)
Read: for each paragraph in order, the first line's text in Word's print: does it end with the piece
("…重复列出了DB" / "…了库") or is the piece on the next line? The T at which it flips is Word's limit.
build.py SRC.docx OUTDIR   (SRC = test/corpus/docx/docs/zh-cd8987db*.docx)"""
import sys, re, zipfile, os
src, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode('utf-8')
text = lambda s: ''.join(re.findall(r'<w:t[^>]*>([^<]*)', s))
paras = list(re.finditer(r'<w:p[ >](?:(?!<w:p[ >]).)*?</w:p>', doc, flags=re.S))
para = [m.group(0) for m in paras if '重复列出了DB' in text(m.group(0))][0]
m = re.match(r'(<w:p[^>]*>)(<w:pPr>.*?</w:pPr>)?(.*)</w:p>$', para, flags=re.S)
ppr, body0 = m.group(2), m.group(3)
SP = '<w:t xml:space="preserve"> </w:t>'
def variant(name):
    b = body0
    removed = 0.0
    if name in ('sp1', 'sp0'):
        # the first run "DB" + its space run, and "5308/T 5" -> "5308/T5"
        b = b.replace('<w:t>DB</w:t></w:r><w:r><w:rPr><w:rFonts w:hint="eastAsia" w:hAnsi="宋体"/><w:szCs w:val="21"/><w:lang w:val="en-US" w:eastAsia="zh-CN"/></w:rPr><w:t xml:space="preserve"> </w:t>', '<w:t>DB</w:t></w:r><w:r><w:t></w:t>', 1)
        b = b.replace('<w:t>5308/T 5</w:t>', '<w:t>5308/T5</w:t>', 1)
        removed = 3.96 + 3.84
    if name == 'sp0':
        b = b.replace('<w:t>7-2020</w:t></w:r><w:r><w:rPr><w:rFonts w:hint="eastAsia" w:hAnsi="宋体"/><w:szCs w:val="21"/><w:lang w:val="en-US" w:eastAsia="zh-CN"/></w:rPr><w:t xml:space="preserve"> </w:t>', '<w:t>7-2020</w:t></w:r><w:r><w:t></w:t>', 1)
        removed += 5.16
    if name == 'ideo':
        i = b.index('以下重复列出了')
        j = b.index('<w:t>DB</w:t>', i)
        b = b[:j] + '<w:t>库</w:t>' + b[j + len('<w:t>DB</w:t>'):]
    return b, removed
own = re.search(r'<w:sectPr[ >].*?</w:sectPr>', doc[doc.index(para):], flags=re.S).group(0)
for name in ('sp3', 'sp1', 'sp0', 'ideo'):
    body, removed = variant(name)
    ps = []
    for k in range(56):
        T = 1.0 + 0.2 * k
        right = round((T + removed - 4.8) * 20)
        p = ppr.replace('<w:ind w:firstLine="420"/>', '<w:ind w:right="%d" w:firstLine="420"/>' % right, 1)
        ps.append('<w:p>%s%s</w:p>' % (p, body))
    d = re.sub(r'(<w:body>).*(</w:body>)', lambda k: k.group(1) + ''.join(ps) + own + k.group(2), doc, count=1, flags=re.S)
    path = os.path.join(outdir, 'dbw-%s.docx' % name)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in z.namelist():
            zo.writestr(n, d.encode('utf-8') if n == 'word/document.xml' else z.read(n))
    print(name, len(ps), 'paragraphs, removed', removed, '->', path)
