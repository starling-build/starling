#!/usr/bin/env python3
"""Lab lef (for amd-opus): where does Word for Windows stop taking the last piece of a line? Three of the
handed-over line-end misses, each its document's own paragraph (styles, settings, runs as they are), copied
with the right indent stepped so the piece's overhang walks across the edge:
  e68  zh-e68a2f57's "（一）住宅建筑…最小间距按表4—1控制。" (mode 14, compressPunctuation, useAltKinsoku):
       Word sends "4—1" down at 1.8pt over, the "）" of the opening "（一）" its only mark; ours takes the "4".
  x621 zh-621d8756's "您好，我们是××机关…今天要对××情况…" (same settings): Word ends "…今天要对" with "×"
       4.7pt over and three marks able to give 21; ours takes one "×".
  cf8  zh-cf8b03a5's cell "指標1×50%＋指標2×50%【註…" (mode 14, doNotCompress, spacing -16): Word takes the last
       "%" where ours misses it by 0.01pt.
Right indent: e68 and x621 from -200 to +200 twips by 20 (21 paragraphs each); cf8 from -60 to +60 by 4 (31).
Read: for each paragraph, in order, the text of its FIRST line in Word's print (and whether the piece is on it).
gen.py CASE SRC.docx OUT.docx   (CASE e68 | x621 | cf8; SRC from test/corpus/docx/docs)"""
import sys, re, zipfile
case, src, out = sys.argv[1], sys.argv[2], sys.argv[3]
needle = {'e68': '住宅建筑各类朝向平行相对布置时的最小间距按表', 'x621': '今天要对', 'cf8': '指標1×50%＋指標2×50%'}[case]
lo, hi, step = (-200, 200, 20) if case != 'cf8' else (-60, 60, 4)
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode('utf-8')
text = lambda s: ''.join(re.findall(r'<w:t[^>]*>([^<]*)', s))
paras = list(re.finditer(r'<w:p[ >](?:(?!<w:p[ >]).)*?</w:p>', doc, flags=re.S))
para = [m.group(0) for m in paras if needle in text(m.group(0))][0]
m = re.match(r'(<w:p[^>]*>)(<w:pPr>.*?</w:pPr>)?(.*)</w:p>$', para, flags=re.S)
ppr = m.group(2) or '<w:pPr></w:pPr>'
body = m.group(3)
out_paras = []
for right in range(lo, hi + 1, step):
    if '<w:ind ' in ppr:
        p = re.sub(r'<w:ind ([^>]*?)/>', lambda k: '<w:ind ' + re.sub(r'\s*w:right(Chars)?="[^"]*"', '', k.group(1)) + ' w:right="%d"/>' % right, ppr, count=1)
    else:
        p = ppr.replace('<w:pPr>', '<w:pPr><w:ind w:right="%d"/>' % right, 1)
    one = '<w:p>%s%s</w:p>' % (p, body)
    if case == 'cf8':
        # (Kept in a table of one cell, its own cell's width and properties, the table's own.)
        i = doc.index(para)
        tc0 = doc.rindex('<w:tc>', 0, i) if '<w:tc>' in doc[:i] else doc.rindex('<w:tc ', 0, i)
        tcpr = re.search(r'<w:tcPr>.*?</w:tcPr>', doc[tc0:i], flags=re.S)
        tb0 = doc.rindex('<w:tbl>', 0, i)
        tblpr = re.search(r'<w:tblPr>.*?</w:tblPr>', doc[tb0:i], flags=re.S).group(0)
        tcp = tcpr.group(0) if tcpr else '<w:tcPr/>'
        tcp = re.sub(r'<w:(gridSpan|vMerge|hMerge)[^>]*/>', '', tcp)
        # (Its table is laid out automatically; fixed here at the cell's text width in Word's print, 118.3pt.)
        w = '2366'
        tcp = re.sub(r'<w:tcW [^>]*/>', '', tcp).replace('<w:tcPr>', '<w:tcPr><w:tcW w:w="2366" w:type="dxa"/>', 1)
        tblpr = tblpr.replace('</w:tblPr>', '<w:tblLayout w:type="fixed"/></w:tblPr>') if '<w:tblLayout' not in tblpr else tblpr
        one = ('<w:tbl>%s<w:tblGrid><w:gridCol w:w="%s"/></w:tblGrid><w:tr><w:tc>%s%s</w:tc></w:tr></w:tbl><w:p/>'
               % (re.sub(r'<w:tblW [^>]*/>', '<w:tblW w:w="%s" w:type="dxa"/>' % w, tblpr), w, tcp, one))
    out_paras.append(one)
# (The section the paragraph stands in — the next section break after it — as the only one.)
at = doc.index(para)
own = re.search(r'<w:sectPr[ >].*?</w:sectPr>', doc[at:], flags=re.S).group(0)
d = re.sub(r'(<w:body>).*(</w:body>)', lambda k: k.group(1) + ''.join(out_paras) + own + k.group(2), doc, count=1, flags=re.S)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zo:
    for n in z.namelist():
        zo.writestr(n, d.encode('utf-8') if n == 'word/document.xml' else z.read(n))
print(case, len(out_paras), 'paragraphs')
