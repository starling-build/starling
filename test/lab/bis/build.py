#!/usr/bin/env python3
"""Lab bis (Windows 01QbbApP, for amd-5): zh-147bdae0 p19 table (the 18-row table holding 其他參與人員 / 相關政府機關人員 / 公民社會團體...), alone in the original package
(styles, theme, numbering, rels kept; body = that table + sectPr). Variants strip ONE property from the table XML:
 v0 as is | v1 all tblCellSpacing (tblPr + every trPr) | v2 only the per-row trPr tblCellSpacing | v3 only tblPr tblCellSpacing | v4 vAlign | v5 trHeight | v6 tblCellMar (tblPr) |
 v7 tblW pct 5000 -> dxa 9000 | v8 shd | v11 tblCellMar top/bottom 216 | v12 no tblCellMar and every tblCellSpacing w=40 | v9 vMerge continue/restart removed (cells independent) | v10 tcMar in cells
usage: build.py src.docx OUTDIR   (src = test/corpus/docx/docs/zh-147bdae0*.docx)"""
import re, sys, os, zipfile
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src); data = {n: z.read(n) for n in z.namelist() if not n.endswith('/')}
d = data['word/document.xml'].decode('utf-8')
def tags():
    return [(m.start(), m.group(0)) for m in re.finditer(r'</?w:(?:tbl|tr|tc)(?=[ >])[^>]*>', d)]
def span(start, kind):
    depth = 0
    for pos, tg in tags():
        if pos < start: continue
        if re.match(r'</?w:(\w+)', tg).group(1) != kind: continue
        depth += -1 if tg.startswith('</') else 1
        if depth == 0: return start, pos + len('</w:%s>' % kind)
def enclosing(idx):
    st = []
    for pos, tg in tags():
        if pos > idx: break
        if re.match(r'</?w:(\w+)', tg).group(1) != 'tbl': continue
        if tg.startswith('</'): st.pop()
        else: st.append(pos)
    return st
i = d.find('張代理處長富林'); st = enclosing(i); assert len(st) == 1, st
a, b = span(st[0], 'tbl'); T = d[a:b]
head = d[:d.index('<w:body>') + 8]
sect = re.findall(r'<w:sectPr.*?</w:sectPr>', d, re.S)[-1]
sect = re.sub(r'<w:(?:header|footer)Reference[^>]*/>', '', sect)
V = {
 'v0': T,
 'v1': re.sub(r'<w:tblCellSpacing [^>]*/>', '', T),
 'v2': re.sub(r'(<w:trPr>.*?)<w:tblCellSpacing [^>]*/>', r'\1', T, flags=re.S) if False else re.sub(r'(?<=<w:trPr>)((?:(?!</w:trPr>).)*?)<w:tblCellSpacing [^>]*/>', r'\1', T, flags=re.S),
 'v3': re.sub(r'(?<=<w:tblPr>)((?:(?!</w:tblPr>).)*?)<w:tblCellSpacing [^>]*/>', r'\1', T, count=1, flags=re.S),
 'v4': re.sub(r'<w:vAlign [^>]*/>', '', T),
 'v5': re.sub(r'<w:trHeight [^>]*/>', '', T),
 'v6': re.sub(r'<w:tblCellMar>.*?</w:tblCellMar>', '', T, count=1, flags=re.S),
 'v7': T.replace('<w:tblW w:w="5000" w:type="pct"/>', '<w:tblW w:w="9000" w:type="dxa"/>', 1),
 'v8': re.sub(r'<w:shd [^>]*/>', '', T),
 'v9': re.sub(r'<w:vMerge[^>]*/>', '', T),
 'v10': re.sub(r'<w:tcMar>.*?</w:tcMar>', '', T, flags=re.S),
 'v11': T.replace('<w:tblCellMar><w:top w:w="108" w:type="dxa"/><w:bottom w:w="108" w:type="dxa"/>', '<w:tblCellMar><w:top w:w="216" w:type="dxa"/><w:bottom w:w="216" w:type="dxa"/>', 1),
 'v12': re.sub(r'<w:tblCellSpacing w:w="0" ', '<w:tblCellSpacing w:w="40" ', re.sub(r'<w:tblCellMar>.*?</w:tblCellMar>', '', T, count=1, flags=re.S)),
}
for k, t in V.items():
    g = dict(data); g['word/document.xml'] = (head + t + '<w:p/>' + sect + '</w:body></w:document>').encode('utf-8')
    with zipfile.ZipFile(os.path.join(out, 'bis-%s.docx' % k), 'w', zipfile.ZIP_DEFLATED) as o:
        for n, bts in g.items(): o.writestr(n, bts)
    print(k, len(t), 'cellspacing', t.count('tblCellSpacing'), 'vAlign', t.count('vAlign'), 'trHeight', t.count('trHeight'), 'shd', t.count('<w:shd'), 'tcMar', t.count('<w:tcMar'))
