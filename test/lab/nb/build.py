#!/usr/bin/env python3
"""Lab nb (Windows 01QbbApP, for amd-5, zh-cb57eaad): the last outer table of the doc (1 row x 1 cell, purple outset border; the cell holds table A (one row, trHeight 13750 = 687.5pt) with a nested table,
then an EMPTY paragraph (spacing line 0 atLeast, mark 微軟正黑體, szCs 24 only) as the outer cell's last paragraph), alone in the original package (body = table + the doc's trailing empty paragraph + sectPr, A4, margins 567/720/709/720, docGrid lines 360).
Variants:  a as is | b 12pt mark (sz 24) AND docGrid removed | b2 docGrid removed only | b3 12pt mark only (grid kept) | c the empty paragraph holds one char 'x' (grid kept) | c2 'x' + 12pt + no grid |
 d outer table gets a second row (plain one-line cell) below the first (as a): outer row is not the last | d2 as d, but 12pt mark + no grid
usage: build.py src.docx OUTDIR"""
import re, sys, os, zipfile
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src); data = {n: z.read(n) for n in z.namelist() if not n.endswith('/')}
d = data['word/document.xml'].decode('utf-8')
tg = [(m.start(), m.group(0)) for m in re.finditer(r'</?w:tbl(?=[ >])[^>]*>', d)]
st = []; tops = []
for pos, t in tg:
    if t.startswith('</'):
        s = st.pop()
        if not st: tops.append((s, pos + len('</w:tbl>')))
    else: st.append(pos)
a, b = tops[-1]; T = d[a:b]
head = d[:d.index('<w:body>') + 8]
sect = re.findall(r'<w:sectPr.*?</w:sectPr>', d, re.S)[-1]
sect = re.sub(r'<w:(?:header|footer)Reference[^>]*/>', '', sect)
tailp = d[b:d.index('<w:sectPr', b)]
cut = T.rfind('</w:tbl><w:p ') + len('</w:tbl>'); end = T.rfind('</w:tc></w:tr></w:tbl>')
P = T[cut:end]; assert P.endswith('</w:p>') and '<w:t' not in P
def sz(p): return p.replace('<w:szCs w:val="24"/></w:rPr></w:pPr>', '<w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:pPr>')
def ch(p): return p.replace('</w:pPr></w:p>', '</w:pPr><w:r><w:rPr><w:rFonts w:ascii="微軟正黑體" w:eastAsia="微軟正黑體" w:hAnsi="微軟正黑體"/></w:rPr><w:t>x</w:t></w:r></w:p>')
def nogrid(s): return re.sub(r'<w:docGrid[^>]*/>', '', s)
ROW2 = '<w:tr><w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr><w:p><w:r><w:t>second outer row</w:t></w:r></w:p></w:tc></w:tr>'
def table(p): return T[:cut] + p + T[end:]
def with_row(t): return t[:-len('</w:tbl>')] + ROW2 + '</w:tbl>'
V = {
 'a': (table(P), sect), 'b': (table(sz(P)), nogrid(sect)), 'b2': (table(P), nogrid(sect)), 'b3': (table(sz(P)), sect),
 'c': (table(ch(P)), sect), 'c2': (table(ch(sz(P))), nogrid(sect)),
 'd': (with_row(table(P)), sect), 'd2': (with_row(table(sz(P))), nogrid(sect)),
}
for k, (t, s) in V.items():
    g = dict(data); g['word/document.xml'] = (head + t + tailp + s + '</w:body></w:document>').encode('utf-8')
    with zipfile.ZipFile(os.path.join(out, 'nb-%s.docx' % k), 'w', zipfile.ZIP_DEFLATED) as o:
        for n, bts in g.items(): o.writestr(n, bts)
print(len(V), 'docs; empty paragraph:', P[:140])
