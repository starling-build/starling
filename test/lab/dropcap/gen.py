#!/usr/bin/env python3
"""Lab dropcap (Windows 01QbbApP, for lenovo-5): drop-cap dash placement, from lo-e6dce9d6fbaa479a (tdf150200).
Each doc = the original's first pair (drop-cap paragraph + 6-line body paragraph) with the char/size swapped; one page each.
Cases: A '-' 260, B en dash 275, C em dash 275, D figure dash U+2012 260, E 'L' 260, F 'L' 275, G '-' 100, H '-' 160. Plus 'orig' = the original verbatim.
usage: gen.py ORIG.docx OUT"""
import sys, os, re, zipfile
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
f = {n: z.read(n) for n in z.namelist()}
d = f['word/document.xml'].decode('utf-8')
bs = d.index('<w:body>') + len('<w:body>')
sect = re.findall(r'<w:sectPr.*?</w:sectPr>', d, re.S)[-1]
p1 = d.index('</w:p>', bs) + 6
p2 = d.index('</w:p>', p1) + 6
cap, body = d[bs:p1], d[p1:p2]
assert '<w:t>-</w:t>' in cap and 'sz w:val="260"' in cap
CASES = {'A': ('-', 260), 'B': ('–', 275), 'C': ('—', 275), 'D': ('‒', 260), 'E': ('L', 260), 'F': ('L', 275), 'G': ('-', 100), 'H': ('-', 160)}
for k, (ch, sz) in CASES.items():
    c = cap.replace('<w:t>-</w:t>', '<w:t>%s</w:t>' % ch).replace('w:val="260"', 'w:val="%d"' % sz)
    s = d[:bs] + c + body + sect + '</w:body></w:document>'
    g = dict(f)
    g['word/document.xml'] = s.encode('utf-8')
    with zipfile.ZipFile(os.path.join(out, 'dc_%s.docx' % k), 'w', zipfile.ZIP_DEFLATED) as o:
        for n, v in g.items():
            o.writestr(n, v)
with zipfile.ZipFile(os.path.join(out, 'dc_orig.docx'), 'w', zipfile.ZIP_DEFLATED) as o:
    for n, v in f.items():
        o.writestr(n, v)
print('ok')
