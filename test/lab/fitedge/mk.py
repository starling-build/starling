#!/usr/bin/env python3
"""fit-edge lab: real paragraph/table from zh-6a4fc013 and zh-202582e2, one change per variant.
usage: mk.py <docs dir> <out dir>"""
import sys, re, zipfile, glob, os
docs, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
def load(pref):
    p = glob.glob(f"{docs}/{pref}*.docx")[0]
    z = zipfile.ZipFile(p)
    return {n: z.read(n) for n in z.namelist()}
def build(pkg, name, body_fn=None, settings_fn=None):
    pkg = dict(pkg)
    d = pkg['word/document.xml'].decode()
    if body_fn: d = body_fn(d)
    pkg['word/document.xml'] = d.encode()
    if settings_fn: pkg['word/settings.xml'] = settings_fn(pkg['word/settings.xml'].decode()).encode()
    with zipfile.ZipFile(f"{out}/{name}.docx", 'w', zipfile.ZIP_DEFLATED) as z:
        for n, b in pkg.items(): z.writestr(n, b)
def only(el_start_marker, kind):
    def f(d):
        i = d.find(el_start_marker)
        if kind == 'p':
            j = max(d.rfind('<w:p ', 0, i), d.rfind('<w:p>', 0, i)); k = d.find('</w:p>', i) + 6
        else:
            j = d.rfind('<w:tbl>', 0, i); k = d.find('</w:tbl>', i) + 8
        el = d[j:k]
        b0 = d.find('<w:body>') + 8
        sect = d[d.rfind('<w:sectPr'):d.rfind('</w:body>')]
        return d[:b0] + el + ('<w:p/>' if kind == 't' else '') + sect + d[d.rfind('</w:body>'):]
    return f
def chain(*fs):
    def f(x):
        for g in fs: x = g(x)
        return x
    return f
# ---- a: zh-6a4fc013 回答 paragraph (compat 15, compressPunctuation, 16 pt 標楷體, margins 1276/1274)
A = load('zh-6a4fc013')
mark = '回答：檢疫及自主'
def txt_swap(a, b):
    return lambda d: d.replace(a, b)
def setset(a, b):
    return lambda s: s.replace(a, b)
base = only('檢疫及自主健康管理期間入住', 'p')
build(A, 'a00-orig', base)
build(A, 'a01-doNotCompress', base, setset('compressPunctuation', 'doNotCompress'))
build(A, 'a02-compat12', base, setset('w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"', 'w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="12"'))
build(A, 'a03-comma-for-dun', chain(base, txt_swap('、', '，')))
build(A, 'a04-jc-left', chain(base, txt_swap('<w:jc w:val="both"/>', '<w:jc w:val="left"/>')))
build(A, 'a05-no-hanging', chain(base, txt_swap('w:ind w:left="961" w:hangingChars="300" w:hanging="961"', 'w:ind w:left="0"')))
build(A, 'a06-text-before-dun-shorter', chain(base, txt_swap('前往本部指定地點之交通費用', '前往本部指定地點交通費用')))
for n, dx in (('a07-right+20', 20), ('a08-right-20', -20), ('a09-right+60', 60), ('a10-right-60', -60)):
    build(A, n, chain(base, lambda d, dx=dx: re.sub(r'w:right="(\d+)"', lambda m: f'w:right="{int(m.group(1))+dx}"', d)))
# ---- b: zh-202582e2 closing table (doNotCompress, compat 14)
B = load('zh-202582e2')
tb = only('抄送：市委办', 't')
build(B, 'b00-orig', tb)
for n, w in (('b01-cell+60', 3686), ('b02-cell-60', 3566), ('b03-cell+200', 3826), ('b04-cell-200', 3426)):
    build(B, n, chain(tb, lambda d, w=w: d.replace('w:w="3626"', f'w:w="{w}"').replace('w:w="8822"', f'w:w="{5196+w}"')))
build(B, 'b05-no-indent', chain(tb, lambda d: re.sub(r'(<w:ind )[^>]*?w:left="830"[^>]*/>', '<w:ind w:left="0"/>', d)))
build(B, 'b06-no-run-spacing', chain(tb, lambda d: re.sub(r'<w:spacing w:val="[^"]*"/>', '', d)))
build(B, 'b07-compat15', tb, setset('w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="14"', 'w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"'))
build(B, 'b08-compress', tb, setset('doNotCompress', 'compressPunctuation'))
print(sorted(os.listdir(out)))
