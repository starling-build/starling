#!/usr/bin/env python3
"""Lab ec (Windows 01QbbApP, for amd-5): how far past the bottom margin may an EMPTY paragraph's line hang before Word sends it (and what follows) to the next page.
Base = lo/zh package zh-e2dc9dce (styles, theme, compat 14, A4, margins 1440/1558, docGrid lines). Body replaced.
Per variant one doc; each CASE = 36 filler paragraphs (exact 18pt, TNR 12) + 1 filler paragraph (exact F twips) so that the room left on the page is T pt,
then ONE empty paragraph (mark per variant), then a paragraph 'X'. Each case starts with pageBreakBefore. Text height 13958 tw.
Variants: a 16pt 標楷體 pitch 360;  b 14pt 方正小标宋 pitch 312;  c 12pt 標楷體 pitch 360.
usage: build.py src.docx OUTDIR -> OUTDIR/eca.docx ecb.docx ecc.docx ; TS in cases.txt"""
import sys, os, re, zipfile
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
f = {n: z.read(n) for n in z.namelist()}
d = f['word/document.xml'].decode('utf-8')
head = d[:d.index('<w:body>') + 8]
TEXTH = 13958
TS = [k * 0.5 for k in range(0, 29)] + [float(t) for t in range(15, 41)]
if os.environ.get('TSFINE'):  # round 2: 0.1pt steps around each variant's threshold (a 27-28, b 23-24, c 15-16 and 33-34)
    TS = [round(b + k * 0.1, 1) for b in (15, 23, 27, 33) for k in range(0, 11)]
V = {'a': ('標楷體', 32, 360), 'b': ('方正小标宋', 28, 312), 'c': ('標楷體', 24, 360)}
RF = '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="%s"/>'
def fill(text, h, brk):
    return ('<w:p><w:pPr>%s<w:spacing w:line="%d" w:lineRule="exact"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="新細明體"/><w:sz w:val="24"/></w:rPr><w:t>%s</w:t></w:r></w:p>'
            % ('<w:pageBreakBefore/>' if brk else '', h, text))
def case(T, face, sz, ci):
    twT = round(T * 20)
    F = TEXTH - 36 * 360 - twT
    assert F > 0
    s = fill('K%02d' % ci, 360, True) + ''.join(fill('filler', 360, False) for _ in range(35)) + fill('filler-last', F, False)
    s += '<w:p><w:pPr><w:rPr>%s<w:sz w:val="%d"/></w:rPr></w:pPr></w:p>' % (RF % face, sz)
    s += '<w:p><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="新細明體"/><w:sz w:val="24"/></w:rPr><w:t>X%02d</w:t></w:r></w:p>' % ci
    return s
for k, (face, sz, pitch) in V.items():
    body = ''.join(case(T, face, sz, i) for i, T in enumerate(TS))
    sect = ('<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1558" w:bottom="1440" w:left="1560" w:header="851" w:footer="850" w:gutter="0"/>'
            '<w:cols w:space="425"/><w:docGrid w:type="lines" w:linePitch="%d"/></w:sectPr>' % pitch)
    g = dict(f); g['word/document.xml'] = (head + body + sect + '</w:body></w:document>').encode('utf-8')
    # the header/footer references are dropped with the old sectPr; their parts stay in the package, harmless
    with zipfile.ZipFile(os.path.join(out, 'ec%s.docx' % k), 'w', zipfile.ZIP_DEFLATED) as o:
        for n, v in g.items(): o.writestr(n, v)
open(os.path.join(out, 'cases.txt'), 'w').write('\n'.join('%02d\t%s' % (i, T) for i, T in enumerate(TS)) + '\n')
print(len(TS), 'cases')
