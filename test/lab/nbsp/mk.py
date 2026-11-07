#!/usr/bin/env python3
"""nbsp lab: does Word stretch/squeeze U+00A0 on a justified line like a word space?
Package, fonts and compat from zh-ea70c30e (PMingLiU 12.5 pt, zh-TW). Each doc holds 9 paragraphs of the
same text with the right indent stepping 0..8 pt (slack on line 1 changes by 1 pt a step).
  n-cjk-nbsp   : CJK list with "nbsp - nbsp" groups (the zh-ea70c30e line)
  s-cjk-space  : same with U+0020 (control)
  l-latin-nbsp : Latin words, every other gap a nbsp
  l-latin-space: Latin words, plain spaces (control)
usage: mk.py <docs dir> <out dir>"""
import sys, zipfile, glob, os
docs, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
p = glob.glob(f"{docs}/zh-ea70c30e*.docx")[0]
z = zipfile.ZipFile(p); pkg = {n: z.read(n) for n in z.namelist()}
d = pkg['word/document.xml'].decode()
b0 = d.find('<w:body>') + 8; sect = d[d.rfind('<w:sectPr'):d.rfind('</w:body>')]
NB = ' '
cjk = '警察服務{s}–{s}資料課；警察服務{s}–{s}巡邏服務台；警察服務{s}–{s}交通課；動物管制單位；公共工程局{s}–{s}行政辦事單位；非法傾倒專線服務；垃圾服務單位；街道照明維修單位；掃街單位'
lat_n = 'The{n}quick brown{n}fox jumps{n}over the{n}lazy dog and{n}keeps running{n}far beyond the{n}quiet river{n}bank today and{n}all the{n}next week as well'
def para(text, r, ascii_run):
    rpr = '<w:rPr><w:rFonts w:ascii="%s" w:hAnsi="%s" w:cs="%s" w:hint="eastAsia"/><w:color w:val="000000"/><w:sz w:val="25"/><w:szCs w:val="25"/><w:lang w:eastAsia="zh-TW"/></w:rPr>' % ((ascii_run,)*3)
    return ('<w:p><w:pPr><w:autoSpaceDE w:val="0"/><w:autoSpaceDN w:val="0"/><w:adjustRightInd w:val="0"/><w:ind w:left="0" w:right="%d"/><w:jc w:val="both"/>%s</w:pPr><w:r>%s<w:t xml:space="preserve">%s</w:t></w:r></w:p><w:p/>' % (r, rpr, rpr, text))
variants = {
 'n-cjk-nbsp': (cjk.format(s=NB), 'PMingLiU'),
 's-cjk-space': (cjk.format(s=' '), 'PMingLiU'),
 'l-latin-nbsp': (lat_n.format(n=NB), 'Times New Roman'),
 'l-latin-space': (lat_n.format(n=' '), 'Times New Roman'),
}
for name, (txt, f) in variants.items():
    body = ''.join(para(txt, 20 * k, f) for k in range(9))
    nd = d[:b0] + body + sect + d[d.rfind('</w:body>'):]
    pk = dict(pkg); pk['word/document.xml'] = nd.encode()
    with zipfile.ZipFile(f"{out}/{name}.docx", 'w', zipfile.ZIP_DEFLATED) as zz:
        for n, bb in pk.items(): zz.writestr(n, bb)
print(sorted(os.listdir(out)))
