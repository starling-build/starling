#!/usr/bin/env python3
"""Lab footx (Windows 01QbbApP, for amd-4): zh-51af781b's footers hold [line anchor run][run 'X' 16pt][bold text ...], jc right, wordWrap 0, ind left 5016 firstLine 6400.
Variants of the real document: orig (verbatim), noX (the X run deleted), Y (the X run's text 'Y'), Z (X -> 'Y' with colour auto & bold, same run props otherwise).
usage: build.py SRC.docx OUTDIR"""
import sys, os, re, zipfile
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
XR = re.compile(r'<w:r>(?:(?!</w:r>).)*?<w:t[^>]*>X</w:t></w:r>', re.S)
def make(name, fn):
    with zipfile.ZipFile(os.path.join(out, name + '.docx'), 'w', zipfile.ZIP_DEFLATED) as o:
        for n in z.namelist():
            b = z.read(n)
            if re.match(r'word/footer\d+\.xml$', n):
                b = fn(b.decode('utf-8')).encode('utf-8')
            o.writestr(n, b)
make('fx_orig', lambda x: x)
make('fx_noX', lambda x: XR.sub('', x))
make('fx_Y', lambda x: XR.sub(lambda m: m.group(0).replace('>X<', '>Y<'), x))
make('fx_YZ', lambda x: XR.sub(lambda m: m.group(0).replace('>X<', '>YZ<'), x))
make('fx_Y3', lambda x: XR.sub(lambda m: m.group(0).replace('>X<', '>Y<') * 3, x))
print('ok')
