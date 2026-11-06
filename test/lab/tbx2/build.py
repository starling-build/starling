#!/usr/bin/env python3
"""Lab tbx2 (for Windows, from lenovo-2): the real zh-8e8d4c40 first paragraph (a wrapSquare text box + the bold 14pt line
"政府補助款經費科目及編列原則" under it) followed by the table's first row, in the REAL document's package (settings, styles, header,
fonts: compat mode 15) — tbx (a synthetic package) did not reproduce the document's gap: Word 121.9 vs ours 123.9 baseline.
Layout in ours depends on the whole document (a truncated copy moved the line 12 pt in x), so each case is the WHOLE real document with ONE change in its first paragraph; only PAGE 1 of each print matters.
usage: build.py SOURCE.docx OUTDIR -> OUTDIR/tbx2-cNN.docx (NN = case), OUTDIR/cases.tsv"""
import sys, os, re, zipfile
src, out = sys.argv[1:3]
z = zipfile.ZipFile(src)
x = z.read('word/document.xml').decode()
b0 = x.index('<w:body>') + 8
p_end = x.index('</w:p>', x.index('政府補助款經費科目及編列原則')) + 6
para = x[b0:p_end]
t0 = x.index('<w:tbl>', p_end)
tr_end = x.index('</w:tr>', t0) + 7
tbl = x[t0:tr_end] + '</w:tbl>'
sect = re.findall(r'<w:sectPr.*?</w:sectPr>', x, re.S)[-1]
head = x[:b0]
def rep(s, a, b, n=1):
    assert s.count(a) >= 1, a
    return s.replace(a, b, n)
EXT = '<wp:effectExtent l="0" t="0" r="22860" b="11430"/>'
CASES = [
    ('exact', lambda p: p),
    ('eb=0', lambda p: rep(p, EXT, '<wp:effectExtent l="0" t="0" r="22860" b="0"/>')),
    ('eb=40000', lambda p: rep(p, EXT, '<wp:effectExtent l="0" t="0" r="22860" b="40000"/>')),
    ('h=400000', lambda p: rep(p, 'cy="598170"', 'cy="400000"', 2)),
    ('h=800000', lambda p: rep(p, 'cy="598170"', 'cy="800000"', 2)),
    ('offV=0', lambda p: rep(p, '<wp:posOffset>74295</wp:posOffset>', '<wp:posOffset>0</wp:posOffset>')),
    ('offV=150000', lambda p: rep(p, '<wp:posOffset>74295</wp:posOffset>', '<wp:posOffset>150000</wp:posOffset>')),
    ('distB=114300', lambda p: rep(p, 'distB="0"', 'distB="114300"')),
    ('notbold', lambda p: rep(p, '<w:b/><w:color w:val="000000"/><w:sz w:val="28"/>', '<w:color w:val="000000"/><w:sz w:val="28"/>')),
    ('sz=24', lambda p: rep(p, '<w:b/><w:color w:val="000000"/><w:sz w:val="28"/><w:szCs w:val="28"/>', '<w:b/><w:color w:val="000000"/><w:sz w:val="24"/><w:szCs w:val="24"/>')),
    ('face=標楷體', lambda p: rep(p, '<w:b/><w:color w:val="000000"/><w:sz w:val="28"/>', '<w:rFonts w:ascii="標楷體" w:eastAsia="標楷體" w:hAnsi="標楷體" w:cs="標楷體"/><w:b/><w:color w:val="000000"/><w:sz w:val="28"/>')),
    ('face=PMingLiU', lambda p: rep(p, '<w:b/><w:color w:val="000000"/><w:sz w:val="28"/>', '<w:rFonts w:ascii="PMingLiU" w:eastAsia="PMingLiU" w:hAnsi="PMingLiU" w:cs="PMingLiU"/><w:b/><w:color w:val="000000"/><w:sz w:val="28"/>')),
    ('noindent', lambda p: rep(p, '<w:ind w:firstLineChars="531" w:firstLine="1274"/>', '')),
    ('boxtext-short', lambda p: re.sub(r'(<w:txbxContent>)<w:p .*?</w:p>(</w:txbxContent>)', r'\1<w:p><w:r><w:t>box</w:t></w:r></w:p>\2', p, count=1, flags=re.S)),
]
os.makedirs(out, exist_ok=True)
for i, (n, f) in enumerate(CASES):
    new = x[:b0] + f(para) + x[p_end:]
    with zipfile.ZipFile(os.path.join(out, 'tbx2-c%02d.docx' % i), 'w', zipfile.ZIP_DEFLATED) as o:
        for it in z.infolist():
            o.writestr(it.filename, new.encode() if it.filename == "word/document.xml" else z.read(it.filename))
open(os.path.join(out, 'cases.tsv'), 'w').write(''.join('C%02d\t%s\n' % (i, n) for i, (n, f) in enumerate(CASES)))
print(len(CASES), 'cases')
