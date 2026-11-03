#!/usr/bin/env python3
"""Lab rgap: zh-147bdae0 p19's table alone (Word for Windows leaves 6pt between
the "相關政府機關人員" row and the next, row 2 also 5.7pt taller; ours none).
Row 2's vMerge continuation cell is the only one without tcMar top/bottom 0, so
it takes the table's tblCellMar 108/108; the table and rows say tblCellSpacing 0.
  rgap-a  as is
  rgap-b  continuation cell given tcMar top/bottom 0 like the rest
  rgap-c  tblCellSpacing removed (table and rows)
  rgap-d  tblCellMar top/bottom removed from the table
usage: gen.py SOURCE.docx OUTDIR"""
import sys, re, zipfile, os
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode('utf-8')
i = doc.find('張代理處長富林')
s = doc.rfind('<w:tbl>', 0, i)
e = doc.find('</w:tbl>', i) + len('</w:tbl>')
body_s = doc.find('<w:body>') + len('<w:body>')
sect = doc[doc.rfind('<w:sectPr'):doc.rfind('</w:body>')]
table = doc[s:e]
def build(t):
    return doc[:body_s] + t + '<w:p/>' + sect + doc[doc.rfind('</w:body>'):]
cont = '<w:vMerge/><w:tcBorders>'
assert table.count(cont) >= 1
variants = {
    'a': table,
    'b': table.replace('<w:vMerge/><w:tcBorders>', '<w:vMerge/><w:tcBorders>', 1).replace(
        '<w:vAlign w:val="center"/><w:hideMark/></w:tcPr><w:p w:rsidR="00394680" w:rsidRPr="002420B7" w:rsidRDefault="00394680" w:rsidP="00394680"><w:pPr><w:suppressAutoHyphens',
        '<w:tcMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tcMar><w:vAlign w:val="center"/><w:hideMark/></w:tcPr><w:p w:rsidR="00394680" w:rsidRPr="002420B7" w:rsidRDefault="00394680" w:rsidP="00394680"><w:pPr><w:suppressAutoHyphens'),
    'c': re.sub(r'<w:tblCellSpacing [^>]*/>', '', table),
    'd': table.replace('<w:tblCellMar><w:top w:w="108" w:type="dxa"/><w:bottom w:w="108" w:type="dxa"/></w:tblCellMar>', ''),
}
assert variants['b'] != table and variants['d'] != table and variants['c'] != table
os.makedirs(out, exist_ok=True)
for k, t in variants.items():
    with zipfile.ZipFile(os.path.join(out, f'rgap-{k}.docx'), 'w', zipfile.ZIP_DEFLATED) as o:
        for n in z.namelist():
            o.writestr(n, build(t) if n == 'word/document.xml' else z.read(n))
